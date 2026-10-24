# One meeting's full lifecycle, run inside a single long-lived process so the keep-awake request
# (bound to this process) lasts from the 15-minute confirmation until recording ends.

$script:SessionMutexName = 'Global\ZoomRecorder_Session'

# --- mockable time primitives ---------------------------------------------
function Get-Now { Get-Date }
function Wait-Seconds { param([Parameter(Mandatory, Position = 0)][double]$Seconds) Start-Sleep -Milliseconds ([int]($Seconds * 1000)) }

# --- cross-process state (tray <-> session) ---------------------------------
function Get-StateDir { Join-Path $script:Root 'state' }

function Get-StatePath {
    param([string]$Name)
    $dir = Get-StateDir
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Join-Path $dir $Name
}

function Set-SessionState {
    param([string]$Id, [string]$Name, [Parameter(Mandatory)][ValidateSet('Idle', 'Guarding', 'Recording')][string]$Phase, [datetime]$StartedAt)
    $state = [pscustomobject]@{
        Phase = $Phase; Id = $Id; Name = $Name; Pid = $PID
        StartedAt = if ($StartedAt) { $StartedAt.ToString('yyyy-MM-ddTHH:mm:ss') } else { $null }
    }
    Set-Content -LiteralPath (Get-StatePath 'session.json') -Value (ConvertTo-Json $state) -Encoding UTF8
}

function Get-SessionState {
    $path = Get-StatePath 'session.json'
    $idle = [pscustomobject]@{ Phase = 'Idle'; Id = $null; Name = $null; Pid = $null; StartedAt = $null }
    if (-not (Test-Path -LiteralPath $path)) { return $idle }
    try { $s = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $idle }
    # A session process that died without cleaning up must not leave the tray stuck on "recording".
    if ($s.Phase -ne 'Idle' -and -not (Get-Process -Id $s.Pid -ErrorAction SilentlyContinue)) { return $idle }
    $s
}

function Request-SessionStop { Set-Content -LiteralPath (Get-StatePath 'stop.request') -Value (Get-Date -Format s) }
function Test-StopRequested { Test-Path -LiteralPath (Get-StatePath 'stop.request') }
function Clear-StopRequest {
    $path = Get-StatePath 'stop.request'
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
}

function Get-PendingNotices {
    param([switch]$Clear)
    $path = Get-StatePath 'notices.json'
    $items = @()
    if (Test-Path -LiteralPath $path) {
        # PS 5.1 ConvertFrom-Json emits a JSON array as one object; ForEach-Object unrolls it.
        try { $items = @(Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ }) } catch { $items = @() }
    }
    if ($Clear -and (Test-Path -LiteralPath $path)) { Remove-Item -LiteralPath $path }
    $items
}

function Add-PendingNotice {
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    $items = @(Get-PendingNotices) + $Message
    Set-Content -LiteralPath (Get-StatePath 'notices.json') -Value (ConvertTo-Json -InputObject $items) -Encoding UTF8
}

# --- waiting loops ---------------------------------------------------------
function Wait-Until {
    # Returns $false if the user asked to stop while waiting.
    param([Parameter(Mandatory, Position = 0)][datetime]$Time)
    while (($left = ($Time - (Get-Now)).TotalSeconds) -gt 0) {
        if (Test-StopRequested) { return $false }
        Wait-Seconds ([math]::Min(2, $left))
    }
    $true
}

function Wait-ForZoomMeeting {
    param([int]$TimeoutMinutes = 30)
    $start = Get-Now
    $seenZoom = $false
    while ($true) {
        if (Test-StopRequested) { return 'Stopped' }
        $state = Get-ZoomState
        if ($state -eq 'Meeting' -or $state -eq 'PasswordError') { return $state }
        if ($state -ne 'None') { $seenZoom = $true }
        $elapsed = (Get-Now) - $start
        if (-not $seenZoom -and $elapsed.TotalSeconds -ge 30) { return 'NoResponse' }
        if ($elapsed.TotalMinutes -ge $TimeoutMinutes) { return 'Timeout' }
        Wait-Seconds 2
    }
}

function Watch-Recording {
    param([Parameter(Mandatory)][datetime]$StartedAt, [Parameter(Mandatory)][int]$MaxMinutes)
    $end = $StartedAt.AddMinutes($MaxMinutes)
    while ($true) {
        if (Test-StopRequested) { return 'UserStop' }
        if (Test-SessionLocked) { return 'Locked' }
        if (-not (Test-EVRunning)) { return 'EVCrashed' }
        if ((Get-Now) -ge $end) { return 'MaxDuration' }
        if ((Get-ZoomState) -ne 'Meeting') {
            # Breakout rooms and host hand-overs briefly drop the meeting window; re-check before stopping.
            Wait-Seconds 10
            if ((Get-ZoomState) -ne 'Meeting') { return 'MeetingEnded' }
        }
        Wait-Seconds 5
    }
}

# --- orchestration ---------------------------------------------------------
$script:EndReasons = @{
    MeetingEnded = @{ Status = 'completed'; Text = '会议已结束' }
    MaxDuration  = @{ Status = 'completed'; Text = '达到最长录制时长' }
    UserStop     = @{ Status = 'completed'; Text = '用户手动停止' }
    Locked       = @{ Status = 'failed'; Text = '录制中断：用户手动锁屏' }
    EVCrashed    = @{ Status = 'failed'; Text = '录制中断：EV 进程意外退出' }
}

function Invoke-RecordingSession {
    param([Parameter(Mandatory)][string]$Id, [switch]$Unattended)

    $mutex = New-Object System.Threading.Mutex($false, $script:SessionMutexName)
    if (-not $mutex.WaitOne(0)) { $mutex.Dispose(); return 'AlreadyRunning' }

    $result = 'failed'
    $log = $null
    $meeting = $null
    try { do {
        $meeting = Get-Meeting $Id
        $resumable = $Unattended -and $meeting -and $meeting.status -in 'guarding', 'recording'
        if (-not $meeting -or ($meeting.status -ne 'pending' -and -not $resumable)) { $result = 'Skipped'; break }

        $perth = Get-MeetingPerthTime $meeting
        $log = New-SessionLog $meeting
        $fail = {
            param([string]$Message)
            Write-SessionLog $log $Message
            Add-PendingNotice "$($meeting.name)：$Message"
            Set-MeetingStatus $meeting.id 'failed'
        }

        Enable-KeepAwake
        Set-MeetingStatus $meeting.id 'guarding'
        Set-SessionState -Id $meeting.id -Name $meeting.name -Phase Guarding
        Write-SessionLog $log '进入值守模式（已阻止睡眠和熄屏）'

        if (-not $Unattended) {
            $timeout = [math]::Max(1, [int]($perth.AddSeconds(-10) - (Get-Now)).TotalSeconds)
            if ((Show-SessionConfirmDialog $meeting -TimeoutSeconds $timeout) -eq 'Cancel') {
                Unregister-MeetingTasks $meeting.id
                Set-MeetingStatus $meeting.id 'cancelled'
                Write-SessionLog $log '用户取消录制'
                Complete-SessionLog $log -Status '已取消'
                $result = 'cancelled'; break
            }
        } else {
            Write-SessionLog $log '无人值守启动（未显示确认窗）'
        }

        if ((Get-Now) -ge $perth.AddMinutes($meeting.maxDuration)) {
            & $fail '录制失败：电脑未能按时唤醒，会议已结束'
            Complete-SessionLog $log -Status '失败 - 错过会议'; break
        }
        if (-not (Wait-Until $perth.AddSeconds(-10))) {
            Set-MeetingStatus $meeting.id 'cancelled'
            Write-SessionLog $log '用户在开始前停止'
            Complete-SessionLog $log -Status '已取消'
            $result = 'cancelled'; break
        }
        if (Test-SessionLocked) {
            & $fail '录制失败：系统已锁屏'
            Complete-SessionLog $log -Status '失败 - 系统已锁屏'; break
        }

        Write-SessionLog $log '启动 EV 录屏'
        if (-not (Start-EV)) {
            & $fail '录制失败：EV 启动失败'
            Complete-SessionLog $log -Status '失败 - EV 启动失败'; break
        }

        [void](Wait-Until $perth)
        Write-SessionLog $log "入会: $(Get-ZoomJoinUrl $meeting.meetingID $meeting.password)"
        Start-ZoomJoin -MeetingID $meeting.meetingID -Password $meeting.password
        $join = Wait-ForZoomMeeting -TimeoutMinutes 30
        if ($join -ne 'Meeting') {
            $shot = [IO.Path]::ChangeExtension($log, '.png')
            Save-Screenshot $shot
            $message = switch ($join) {
                'PasswordError' { '入会失败：密码错误' }
                'Stopped' { '用户在入会前停止' }
                default { '入会失败：Zoom 未响应' }
            }
            & $fail $message
            Write-SessionLog $log "截图已保存: $shot"
            Close-Zoom; Close-EV
            Complete-SessionLog $log -Status "失败 - $($message -replace '^.*：', '')"; break
        }
        Write-SessionLog $log 'Zoom 会议窗口已出现'

        Wait-Seconds 5
        if (Confirm-ZoomComputerAudio) { Write-SessionLog $log '已选择使用电脑音频' }
        if (Set-ZoomFullScreen) { Write-SessionLog $log '进入全屏模式' } else { Write-SessionLog $log '警告：未能确认全屏' }
        if (Enable-ZoomCaptions) { Write-SessionLog $log '字幕已打开' } else { Write-SessionLog $log '字幕未打开（可能主持人未启用）' }

        Start-EVRecording
        $startedAt = Get-Now
        Set-MeetingStatus $meeting.id 'recording'
        Set-SessionState -Id $meeting.id -Name $meeting.name -Phase Recording -StartedAt $startedAt
        Write-SessionLog $log '录制开始'

        $reason = Watch-Recording -StartedAt $startedAt -MaxMinutes $meeting.maxDuration
        $end = $script:EndReasons[$reason]
        Write-SessionLog $log $end.Text
        if ($reason -ne 'EVCrashed') {
            Stop-EVRecording
            Write-SessionLog $log '停止 EV 录制'
            Wait-Seconds 3
        }
        Close-Zoom
        $video = Find-EVRecording -Since $startedAt.AddMinutes(-1)
        if ($reason -ne 'EVCrashed') { Wait-EVFileSettled $video }
        Close-EV
        Write-SessionLog $log '关闭 Zoom 和 EV，录制结束'

        if ($end.Status -eq 'failed') {
            & $fail $end.Text
            Complete-SessionLog $log -Status "失败 - $($end.Text)" -Duration ((Get-Now) - $startedAt) -VideoPath $video
        } else {
            Set-MeetingStatus $meeting.id 'completed'
            Complete-SessionLog $log -Status '成功' -Duration ((Get-Now) - $startedAt) -VideoPath $video
        }
        $result = $end.Status
    } while ($false) } catch {
        if ($log) { Write-SessionLog $log "错误: $($_.Exception.Message)" }
        if ($meeting) { Set-MeetingStatus $meeting.id 'failed'; Add-PendingNotice "$($meeting.name)：录制出错 - $($_.Exception.Message)" }
        $result = 'failed'
    } finally {
        if ($result -ne 'Skipped') {
            Disable-KeepAwake
            Clear-StopRequest
            Set-SessionState -Phase Idle
        }
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
    $result
}

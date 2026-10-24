# Windows Task Scheduler integration. Each meeting gets up to three one-shot tasks:
#   Notify12h  perth-12h  balloon reminder
#   Session    perth-15m  confirmation dialog + keep-awake + recording (one long-lived process)
#   Record     perth-3m   wake-from-sleep fallback; runs Session unattended, exits at once if Session already runs

$script:TaskPrefix = 'ZoomRecorder_'

function Get-EntryScriptPath { Join-Path $script:Root 'ZoomRecorder.ps1' }

function Get-MeetingTriggerPlan {
    param([Parameter(Mandatory, Position = 0)]$Meeting, [datetime]$Now = (Get-Date))
    $perth = Get-MeetingPerthTime $Meeting
    $plan = @(
        [pscustomobject]@{ Kind = 'Notify12h'; At = $perth.AddHours(-12); WakeToRun = $false }
        [pscustomobject]@{ Kind = 'Session'; At = $perth.AddMinutes(-15); WakeToRun = $false }
        [pscustomobject]@{ Kind = 'Record'; At = $perth.AddMinutes(-3); WakeToRun = $true }
    )
    $plan | Where-Object { $_.At -gt $Now }
}

function Get-TaskArguments {
    param([Parameter(Mandatory)][ValidateSet('Notify12h', 'Session', 'Record')][string]$Kind, [Parameter(Mandatory)][string]$Id)
    $action = if ($Kind -eq 'Notify12h') { 'Notify12h' } else { 'Session' }
    $args = '-NoProfile -WindowStyle Hidden -STA -File "{0}" -Action {1} -Id {2}' -f (Get-EntryScriptPath), $action, $Id
    if ($Kind -eq 'Record') { $args += ' -Unattended' }
    $args
}

function Get-MeetingTaskNames {
    param([Parameter(Mandatory, Position = 0)][string]$Id)
    @(Get-ScheduledTask -TaskName "$($script:TaskPrefix)*_$Id" -ErrorAction SilentlyContinue | ForEach-Object TaskName)
}

function Unregister-TasksLike {
    param([string]$Pattern)
    foreach ($task in @(Get-ScheduledTask -TaskName $Pattern -ErrorAction SilentlyContinue)) {
        Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false
    }
}

function Unregister-MeetingTasks {
    param([Parameter(Mandatory, Position = 0)][string]$Id)
    Unregister-TasksLike "$($script:TaskPrefix)*_$Id"
}

function Unregister-AllRecorderTasks { Unregister-TasksLike "$($script:TaskPrefix)*" }

function Register-MeetingTasks {
    param([Parameter(Mandatory, Position = 0)]$Meeting)
    Unregister-MeetingTasks $Meeting.id
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    foreach ($item in Get-MeetingTriggerPlan $Meeting) {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (Get-TaskArguments -Kind $item.Kind -Id $Meeting.id)
        $trigger = New-ScheduledTaskTrigger -Once -At $item.At
        $settings = New-ScheduledTaskSettingsSet -WakeToRun:$item.WakeToRun -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 12) -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName ('{0}{1}_{2}' -f $script:TaskPrefix, $item.Kind, $Meeting.id) `
            -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
            -Description "ZoomRecorder: $($Meeting.name) ($($Meeting.meetingID))" | Out-Null
    }
}

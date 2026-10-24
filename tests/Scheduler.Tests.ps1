Import-Module "$PSScriptRoot\..\RecorderCore.psm1" -Force

Describe 'Get-MeetingTriggerPlan' {
    $m = New-MeetingObject -Name x -MeetingID '123456789' -Password '' -OriginalTime ([datetime]'2026-10-29 03:15') -TimeZone 'Asia/Shanghai' -MaxDuration 60

    It '三个触发点' {
        $p = Get-MeetingTriggerPlan $m -Now ([datetime]'2026-10-24')
        ($p | Where-Object Kind -eq 'Notify12h').At | Should Be ([datetime]'2026-10-28 15:15')
        ($p | Where-Object Kind -eq 'Session').At   | Should Be ([datetime]'2026-10-29 03:00')
        ($p | Where-Object Kind -eq 'Record').At    | Should Be ([datetime]'2026-10-29 03:12')
        ($p | Where-Object Kind -eq 'Record').WakeToRun | Should Be $true
        ($p | Where-Object Kind -eq 'Session').WakeToRun | Should Be $false
    }
    It '不足 12 小时：跳过 Notify12h' { (Get-MeetingTriggerPlan $m -Now ([datetime]'2026-10-28 20:00')).Kind -join ',' | Should Be 'Session,Record' }
    It '不足 15 分钟：只剩 Record' { (Get-MeetingTriggerPlan $m -Now ([datetime]'2026-10-29 03:05')).Kind -join ',' | Should Be 'Record' }
    It '已开始：没有任务' { @(Get-MeetingTriggerPlan $m -Now ([datetime]'2026-10-29 03:20')).Count | Should Be 0 }
}

Describe 'Get-TaskArguments' {
    It 'Session 带 Id' { Get-TaskArguments -Kind Session -Id 'abc' | Should Match '-File ".+ZoomRecorder\.ps1" -Action Session -Id abc$' }
    It 'Record 为无人值守 Session' { Get-TaskArguments -Kind Record -Id 'abc' | Should Match '-Action Session -Id abc -Unattended$' }
    It '不使用 ExecutionPolicy Bypass' { Get-TaskArguments -Kind Session -Id 'abc' | Should Not Match 'Bypass' }
}

# ScheduledTasks cmdlets are mocked: the unit suite must not create real tasks on the machine.
# Real registration is checked manually in Task 9 Step 5 / the E2E checklist.
Describe 'Register-MeetingTasks' {
    $now = Get-Date
    $a = New-MeetingObject -Name a -MeetingID '999999999' -Password '' -OriginalTime $now.AddDays(3) -TimeZone 'Asia/Shanghai' -MaxDuration 60
    $b = New-MeetingObject -Name b -MeetingID '999999999' -Password '' -OriginalTime $now.AddDays(10) -TimeZone 'Asia/Shanghai' -MaxDuration 60

    Mock Register-ScheduledTask {} -ModuleName RecorderCore
    Mock Unregister-ScheduledTask {} -ModuleName RecorderCore
    # Only meeting $a "already has" a task. Mock bodies run in module scope, so pass the id via a global.
    $global:ZrExistingId = $a.id
    Mock Get-ScheduledTask {
        if ($TaskName -like "*_$global:ZrExistingId") { [pscustomobject]@{ TaskName = "ZoomRecorder_Session_$global:ZrExistingId" } }
    } -ModuleName RecorderCore

    It '注册 3 个任务，名称用 meeting id' {
        Register-MeetingTasks $a
        foreach ($k in 'Notify12h', 'Session', 'Record') {
            Assert-MockCalled Register-ScheduledTask -ModuleName RecorderCore -Times 1 -Exactly -ParameterFilter { $TaskName -eq "ZoomRecorder_${k}_$($a.id)" }
        }
    }
    It '只有 Record 任务可唤醒' {
        Register-MeetingTasks $a
        Assert-MockCalled Register-ScheduledTask -ModuleName RecorderCore -ParameterFilter { $TaskName -like 'ZoomRecorder_Record_*' -and $Settings.WakeToRun }
        Assert-MockCalled Register-ScheduledTask -ModuleName RecorderCore -Times 0 -Exactly -ParameterFilter { $TaskName -notlike 'ZoomRecorder_Record_*' -and $Settings.WakeToRun }
    }
    It '注册前先删除同 id 旧任务' {
        Register-MeetingTasks $a
        Assert-MockCalled Unregister-ScheduledTask -ModuleName RecorderCore
    }
    It '同会议号删除互不影响' {
        Unregister-MeetingTasks $b.id
        Assert-MockCalled Unregister-ScheduledTask -ModuleName RecorderCore -Times 0 -Exactly -Scope It
    }
}

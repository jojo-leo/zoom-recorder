Import-Module "$PSScriptRoot\..\RecorderCore.psm1" -Force

Describe 'Save-MeetingFromForm' {
    Mock Save-Meeting {} -ModuleName RecorderCore
    Mock Register-MeetingTasks {} -ModuleName RecorderCore
    Mock Unregister-MeetingTasks {} -ModuleName RecorderCore
    Mock Remove-Meeting {} -ModuleName RecorderCore
    Mock Get-Meetings { $global:ZrExisting } -ModuleName RecorderCore
    $global:ZrExisting = @()
    $now = [datetime]'2026-10-24'
    $f = @{ Name = 'S'; MeetingID = '123 456 789'; Password = 'p'; Date = [datetime]'2026-10-28'; Time = '15:15'; TimeZone = 'America/New_York'; MaxDuration = 120 }

    It '有效输入：保存并注册' {
        $r = Save-MeetingFromForm $f -Now $now
        $r.Ok | Should Be $true
        $r.Meeting.perthTime | Should Be '2026-10-29T03:15:00'
        Assert-MockCalled Save-Meeting -ModuleName RecorderCore -Times 1 -Exactly -Scope It
        Assert-MockCalled Register-MeetingTasks -ModuleName RecorderCore -Times 1 -Exactly -Scope It
    }
    It '时间格式错误' {
        $g = $f.Clone(); $g.Time = '25:99'
        $r = Save-MeetingFromForm $g -Now $now
        $r.Ok | Should Be $false
        ($r.Errors -join '') | Should Match '时间'
        Assert-MockCalled Save-Meeting -ModuleName RecorderCore -Times 0 -Exactly -Scope It
    }
    It '缺少日期' { $g = $f.Clone(); $g.Date = $null; ((Save-MeetingFromForm $g -Now $now).Errors -join '') | Should Match '日期' }
    It 'DST 不存在时间：报错不保存' {
        $g = $f.Clone(); $g.Date = [datetime]'2026-03-08'; $g.Time = '02:30'
        $r = Save-MeetingFromForm $g -Now ([datetime]'2026-01-01')
        $r.Ok | Should Be $false
        ($r.Errors -join '') | Should Match '不存在'
    }
    It '会议号错误' { $g = $f.Clone(); $g.MeetingID = '12'; ((Save-MeetingFromForm $g -Now $now).Errors -join '') | Should Match '9-11' }
    It '冲突：不保存，返回冲突；-Force 后保存' {
        $global:ZrExisting = @(New-MeetingObject -Name other -MeetingID '987654321' -Password '' -OriginalTime ([datetime]'2026-10-28 15:45') -TimeZone 'America/New_York' -MaxDuration 60)
        $r = Save-MeetingFromForm $f -Now $now
        $r.Ok | Should Be $false
        @($r.Errors).Count | Should Be 0
        @($r.Conflicts).Count | Should Be 1
        (Save-MeetingFromForm $f -Now $now -Force).Ok | Should Be $true
        $global:ZrExisting = @()
    }
    It '编辑改时间：删除旧任务和旧记录' {
        $old = New-MeetingObject -Name S -MeetingID '123456789' -Password p -OriginalTime ([datetime]'2026-10-27 15:15') -TimeZone 'America/New_York' -MaxDuration 120
        (Save-MeetingFromForm $f -Existing $old -Now $now).Ok | Should Be $true
        Assert-MockCalled Unregister-MeetingTasks -ModuleName RecorderCore -Scope It -ParameterFilter { $Id -eq $old.id }
        Assert-MockCalled Remove-Meeting -ModuleName RecorderCore -Scope It -ParameterFilter { $Id -eq $old.id }
    }
    It '编辑不改时间：不删除' {
        $old = New-MeetingObject -Name S -MeetingID '123456789' -Password p -OriginalTime ([datetime]'2026-10-28 15:15') -TimeZone 'America/New_York' -MaxDuration 120
        Save-MeetingFromForm $f -Existing $old -Now $now | Out-Null
        Assert-MockCalled Remove-Meeting -ModuleName RecorderCore -Times 0 -Exactly -Scope It
    }
}

Describe 'Remove-MeetingWithTasks' {
    Mock Unregister-MeetingTasks {} -ModuleName RecorderCore
    Mock Remove-Meeting {} -ModuleName RecorderCore
    It '删除任务和数据' {
        Remove-MeetingWithTasks 'abc'
        Assert-MockCalled Unregister-MeetingTasks -ModuleName RecorderCore -Times 1 -Exactly -ParameterFilter { $Id -eq 'abc' }
        Assert-MockCalled Remove-Meeting -ModuleName RecorderCore -Times 1 -Exactly -ParameterFilter { $Id -eq 'abc' }
    }
}

Describe 'Get-StatusLabel' {
    It '中文状态' { (Get-StatusLabel 'pending'), (Get-StatusLabel 'guarding'), (Get-StatusLabel 'cancelled') -join ',' | Should Be '待录制,值守中,已取消' }
}

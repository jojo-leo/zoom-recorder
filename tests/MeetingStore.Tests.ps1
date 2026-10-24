Import-Module "$PSScriptRoot\..\RecorderCore.psm1" -Force

Describe 'MeetingStore' {
    $p = Join-Path $TestDrive 'm.json'
    $m = New-MeetingObject -Name '' -MeetingID '123 456-789' -Password 'pw' -OriginalTime ([datetime]'2026-10-28 15:00') -TimeZone 'America/New_York' -MaxDuration 120

    It '规范化会议号与默认名' { $m.meetingID | Should Be '123456789'; $m.name | Should Be 'Meeting_123456789' }
    It 'id 与珀斯时间' { $m.id | Should Be '20261029030000_123456789'; $m.perthTime | Should Be '2026-10-29T03:00:00' }
    It '校验通过' { @(Test-MeetingInput $m -Now ([datetime]'2026-10-24')).Count | Should Be 0 }
    It '会议号过短' { $b = $m.PSObject.Copy(); $b.meetingID = '1234'; (Test-MeetingInput $b -Now ([datetime]'2026-10-24')) -join '' | Should Match '9-11' }
    It '时间已过' { (Test-MeetingInput $m -Now ([datetime]'2026-10-30')) -join '' | Should Match '已过' }
    It '时长越界' { $b = $m.PSObject.Copy(); $b.maxDuration = 0; (Test-MeetingInput $b -Now ([datetime]'2026-10-24')) -join '' | Should Match '1-600' }
    It '文件不存在返回空' { @(Get-Meetings -Path $p).Count | Should Be 0 }
    It '保存并读回' { Save-Meeting $m -Path $p; (Get-Meeting $m.id -Path $p).password | Should Be 'pw' }
    It '同 id 替换而不是追加' { Save-Meeting $m -Path $p; @(Get-Meetings -Path $p).Count | Should Be 1 }
    It '改状态' { Set-MeetingStatus $m.id 'completed' -Path $p; (Get-Meeting $m.id -Path $p).status | Should Be 'completed' }
    It '删除' { Remove-Meeting $m.id -Path $p; @(Get-Meetings -Path $p).Count | Should Be 0 }
    It '文件仅当前用户和 SYSTEM 可访问（含密码）' {
        Save-Meeting $m -Path $p
        $acl = Get-Acl -LiteralPath $p
        $acl.AreAccessRulesProtected | Should Be $true
        $who = @($acl.Access | ForEach-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } | Sort-Object -Unique)
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        ($who | Where-Object { $_ -ne $me -and $_ -ne 'S-1-5-18' }).Count | Should Be 0
        Remove-Meeting $m.id -Path $p
    }
    It '损坏文件报错而不覆盖' {
        Set-Content $p '{oops'
        { Get-Meetings -Path $p } | Should Throw
        { Save-Meeting $m -Path $p } | Should Throw
        Get-Content $p | Should Be '{oops'
    }
    It '时间冲突' {
        $a = New-MeetingObject -Name a -MeetingID '111111111' -Password '' -OriginalTime ([datetime]'2026-10-29 03:00') -TimeZone 'Asia/Shanghai' -MaxDuration 120
        $b = New-MeetingObject -Name b -MeetingID '222222222' -Password '' -OriginalTime ([datetime]'2026-10-29 04:30') -TimeZone 'Asia/Shanghai' -MaxDuration 60
        $c = New-MeetingObject -Name c -MeetingID '333333333' -Password '' -OriginalTime ([datetime]'2026-10-29 05:00') -TimeZone 'Asia/Shanghai' -MaxDuration 60
        @(Find-MeetingConflict $b -Existing @($a)).Count | Should Be 1
        @(Find-MeetingConflict $c -Existing @($a)).Count | Should Be 0
        $a.status = 'completed'
        @(Find-MeetingConflict $b -Existing @($a)).Count | Should Be 0
    }
}

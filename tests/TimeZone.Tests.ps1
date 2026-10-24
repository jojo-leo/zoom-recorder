Import-Module "$PSScriptRoot\..\RecorderCore.psm1" -Force

Describe 'ConvertTo-PerthTime' {
    It 'NY 夏令时 (EDT, UTC-4)' { ConvertTo-PerthTime ([datetime]'2026-10-28 15:00') 'America/New_York' | Should Be ([datetime]'2026-10-29 03:00') }
    It 'NY 冬令时 (EST, UTC-5)' { ConvertTo-PerthTime ([datetime]'2026-11-04 15:00') 'America/New_York' | Should Be ([datetime]'2026-11-05 04:00') }
    It 'London BST' { ConvertTo-PerthTime ([datetime]'2026-07-01 10:00') 'Europe/London' | Should Be ([datetime]'2026-07-01 17:00') }
    It 'London GMT' { ConvertTo-PerthTime ([datetime]'2026-12-01 10:00') 'Europe/London' | Should Be ([datetime]'2026-12-01 18:00') }
    It 'Tokyo' { ConvertTo-PerthTime ([datetime]'2026-10-28 10:00') 'Asia/Tokyo' | Should Be ([datetime]'2026-10-28 09:00') }
    It 'UTC' { ConvertTo-PerthTime ([datetime]'2026-10-28 00:00') 'UTC' | Should Be ([datetime]'2026-10-28 08:00') }
    It '不存在的时间报错' { { ConvertTo-PerthTime ([datetime]'2026-03-08 02:30') 'America/New_York' } | Should Throw }
    It '重复时间按夏令时' { ConvertTo-PerthTime ([datetime]'2026-11-01 01:30') 'America/New_York' | Should Be ([datetime]'2026-11-01 13:30') }
    It '未知时区报错' { { ConvertTo-PerthTime ([datetime]'2026-10-28 10:00') 'Mars/Base' } | Should Throw }
    It '支持 13 个时区' { (Get-SupportedTimeZones).Count | Should Be 13 }
}

# Time zone handling: the user enters meetings in the organiser's IANA zone,
# everything else runs on Perth local time (the machine's own zone).

$script:PerthZoneId = 'W. Australia Standard Time'

# IANA name shown in the UI -> Windows time zone ID understood by .NET Framework.
$script:TimeZoneMap = [ordered]@{
    'America/New_York'    = 'Eastern Standard Time'
    'America/Chicago'     = 'Central Standard Time'
    'America/Los_Angeles' = 'Pacific Standard Time'
    'America/Toronto'     = 'Eastern Standard Time'
    'Europe/London'       = 'GMT Standard Time'
    'Europe/Paris'        = 'Romance Standard Time'
    'Europe/Berlin'       = 'W. Europe Standard Time'
    'Europe/Zurich'       = 'W. Europe Standard Time'
    'Asia/Tokyo'          = 'Tokyo Standard Time'
    'Asia/Shanghai'       = 'China Standard Time'
    'Asia/Singapore'      = 'Singapore Standard Time'
    'Asia/Hong_Kong'      = 'China Standard Time'
    'UTC'                 = 'UTC'
}

function Get-SupportedTimeZones {
    [string[]]@($script:TimeZoneMap.Keys)
}

function ConvertTo-PerthTime {
    param(
        [Parameter(Mandatory)][datetime]$OriginalTime,
        [Parameter(Mandatory)][string]$TimeZone
    )
    if (-not $script:TimeZoneMap.Contains($TimeZone)) {
        throw "不支持的时区: $TimeZone"
    }
    $source = [TimeZoneInfo]::FindSystemTimeZoneById($script:TimeZoneMap[$TimeZone])
    $perth = [TimeZoneInfo]::FindSystemTimeZoneById($script:PerthZoneId)
    $t = [datetime]::SpecifyKind($OriginalTime, [DateTimeKind]::Unspecified)

    if ($source.IsInvalidTime($t)) {
        throw "该时间在 $TimeZone 不存在（夏令时切换跳过了这一小时）: $($t.ToString('yyyy-MM-dd HH:mm'))"
    }
    if ($source.IsAmbiguousTime($t)) {
        # Clock falls back: the hour happens twice. Take the first occurrence (daylight offset, the larger one).
        $offset = $source.GetAmbiguousTimeOffsets($t) | Sort-Object -Descending | Select-Object -First 1
        $utc = (New-Object DateTimeOffset($t, $offset)).UtcDateTime
    } else {
        $utc = [TimeZoneInfo]::ConvertTimeToUtc($t, $source)
    }
    [datetime]::SpecifyKind([TimeZoneInfo]::ConvertTimeFromUtc($utc, $perth), [DateTimeKind]::Unspecified)
}

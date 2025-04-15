function ParseDateRange {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    Param (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $date_str
    )
    $now = $date = Get-Date
    $number, $unit_name = $date_str.Split()
    try {
        $number = - ([int]$number)
    }
    catch [System.Management.Automation.RuntimeException] {
        throw "No number given in '$date_str'"
    }
    if ($null -eq $unit_name) {
        throw "Time unit not given in '$date_str'"
    }
    if (!($unit_name.GetType() -eq [String])) {
        throw "Too many arguemnts in '$date_str'"
    }
    if ($unit_name.Contains("minute")) {
        $date = $date.AddMinutes($number)
    }
    elseif ($unit_name.Contains("hour")) {
        $date = $date.AddHours($number)
    }
    elseif ($unit_name.Contains("day")) {
        $date = $date.AddDays($number)
    }
    elseif ($unit_name.Contains("week")) {
        $date = $date.AddDays($number * 7)
    }
    elseif ($unit_name.Contains("month")) {
        $date = $date.AddMonths($number)
    }
    elseif ($unit_name.Contains("year")) {
        $date = $date.AddYears($number)
    }
    else {
        throw "Could not process time unit '$unit_name'. Available are: minute, hour, day, week, month, year."
    }
    return $date, $now
    <#
      .DESCRIPTION
      Gets a string represents a date range ("3 day", "2 years" etc) and return the time on the past according to
      the date range.

      .PARAMETER date_str
       a date string in a human readable format as "3 days", "5 years".
       Available units: minute, hour, day, week, month, year.

      .EXAMPLE
      ParseDateRange("3 days") (current date it 04/01/21)
      Date(01/01/21)
      #>
}

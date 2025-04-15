<#
.SYNOPSIS
    Adds or subtracts time units from a datetime object.

.DESCRIPTION
    This function allows you to add or subtract years, months, weeks, days, hours, minutes, seconds, and microseconds from a datetime object.
    It also supports setting specific days of the month and weekdays.

.PARAMETER Value
    The input datetime object or string that can be parsed into a datetime. Accepts pipeline input.

.PARAMETER Years
    Number of years to add or subtract from the datetime.

.PARAMETER Months
    Number of months to add or subtract from the datetime.

.PARAMETER Weeks
    Number of weeks to add or subtract from the datetime.

.PARAMETER Days
    Number of days to add or subtract from the datetime.

.PARAMETER Hours
    Number of hours to add or subtract from the datetime.

.PARAMETER Minutes
    Number of minutes to add or subtract from the datetime.

.PARAMETER Seconds
    Number of seconds to add or subtract from the datetime.

.PARAMETER Microseconds
    Number of microseconds to add or subtract from the datetime.

.PARAMETER Day
    The day of the month to set the datetime to. If the day is not valid for the month, the last day of the month is used.

.PARAMETER Weekday
    The day of the week to return. Can be an integer (0-6) or a string (e.g., 'monday', 'tuesday', etc.).

.EXAMPLE
    Add-DateDelta -Value "2020-01-01" -Days 1
    # Returns: 2020-01-02 00:00:00

.EXAMPLE
    Add-DateDelta -Value (Get-Date) -Months 1 -Days 5
    # Adds 1 month and 5 days to the current date

.EXAMPLE
    Add-DateDelta -Value "2020-01-01" -Day 1 -Weekday "monday"
    # Returns the first Monday of January 2020

.EXAMPLE
    "2020-01-01", "2020-02-01" | Add-DateDelta -Days 1
    # Returns dates for 2020-01-02 and 2020-02-02

.EXAMPLE
    Get-ChildItem | Select-Object -ExpandProperty LastWriteTime | Add-DateDelta -Days 7
    # Adds 7 days to the LastWriteTime of all files in the current directory
#>
function Add-DateDelta {
    [CmdletBinding()]
    [OutputType([DateTime])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [object]$Value,

        [Parameter()]
        [int]$Years = 0,

        [Parameter()]
        [int]$Months = 0,

        [Parameter()]
        [int]$Weeks = 0,

        [Parameter()]
        [int]$Days = 0,

        [Parameter()]
        [int]$Hours = 0,

        [Parameter()]
        [int]$Minutes = 0,

        [Parameter()]
        [int]$Seconds = 0,

        [Parameter()]
        [int]$Microseconds = 0,

        [Parameter()]
        [int]$Day,

        [Parameter()]
        [object]$Weekday
    )

    begin {
        # Convert weekday string to number if necessary
        if ($Weekday -is [string]) {
            $weekdayMap = @{
                'sunday' = 0
                'monday' = 1
                'tuesday' = 2
                'wednesday' = 3
                'thursday' = 4
                'friday' = 5
                'saturday' = 6
            }
            $Weekday = $weekdayMap[$Weekday.ToLower()]
            if ($null -eq $Weekday) {
                throw "Invalid weekday string. Must be one of: sunday, monday, tuesday, wednesday, thursday, friday, saturday"
            }
        }
    }

    process {
        try {
            # Convert string input to DateTime if necessary
            if ($Value -is [string]) {
                try {
                    $Value = [DateTime]::Parse($Value)
                }
                catch {
                    throw "Unable to parse the input date string: $_"
                }
            }
            elseif ($Value -isnot [DateTime]) {
                throw "Input must be a DateTime object or a string that can be parsed into a DateTime"
            }

            # Start with the input date
            $result = $Value

            # Add years and months
            if ($Years -ne 0 -or $Months -ne 0) {
                $result = $result.AddYears($Years).AddMonths($Months)
            }

            # Add weeks and days
            if ($Weeks -ne 0 -or $Days -ne 0) {
                $result = $result.AddDays(($Weeks * 7) + $Days)
            }

            # Add time components
            if ($Hours -ne 0) {
                $result = $result.AddHours($Hours)
            }
            if ($Minutes -ne 0) {
                $result = $result.AddMinutes($Minutes)
            }
            if ($Seconds -ne 0) {
                $result = $result.AddSeconds($Seconds)
            }
            if ($Microseconds -ne 0) {
                $result = $result.AddTicks($Microseconds * 10) # 1 tick = 100 nanoseconds
            }

            # Handle day of month
            if ($PSBoundParameters.ContainsKey('Day')) {
                # Get the last day of the month
                $lastDay = [DateTime]::DaysInMonth($result.Year, $result.Month)
                $targetDay = [Math]::Min($Day, $lastDay)
                $result = [DateTime]::new($result.Year, $result.Month, $targetDay, $result.Hour, $result.Minute, $result.Second, $result.Millisecond)
            }

            # Handle weekday
            if ($PSBoundParameters.ContainsKey('Weekday')) {
                $currentWeekday = [int]$result.DayOfWeek
                $daysToAdd = ($Weekday - $currentWeekday) % 7
                if ($daysToAdd -lt 0) {
                    $daysToAdd += 7
                }
                $result = $result.AddDays($daysToAdd)

                # If day is specified, adjust to the correct week
                if ($PSBoundParameters.ContainsKey('Day')) {
                    $weekNumber = [Math]::Floor(($Day - 1) / 7)
                    $result = $result.AddDays($weekNumber * 7)
                }
            }

            return $result
        }
        catch {
            throw "Error calculating date delta: $_"
        }
    }
} 
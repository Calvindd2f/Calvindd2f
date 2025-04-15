<#
.SYNOPSIS
    Formats a datetime object into a string using specified format.

.DESCRIPTION
    This function formats a datetime object into a string using either standard .NET format strings,
    custom format strings, or PowerShell format strings. It supports pipeline input and can handle
    both DateTime objects and date strings.

.PARAMETER Value
    The input datetime object or string that can be parsed into a datetime. Accepts pipeline input.

.PARAMETER Format
    The format specification to use. Can be one of:
    - Standard .NET format strings (e.g., 'd', 'D', 'f', 'F', 'g', 'G', 'm', 'o', 'r', 's', 't', 'T', 'u', 'U', 'y')
    - Custom format strings (e.g., 'yyyy-MM-dd HH:mm:ss')
    - PowerShell format strings (e.g., 'yyyy-MM-dd')

.PARAMETER Culture
    The culture to use for formatting. Defaults to the current culture.

.EXAMPLE
    Format-DateTime -Value (Get-Date) -Format "yyyy-MM-dd"
    # Returns: 2024-03-14

.EXAMPLE
    Format-DateTime -Value "2020-01-01" -Format "D"
    # Returns: Wednesday, January 1, 2020

.EXAMPLE
    Get-Date | Format-DateTime -Format "HH:mm:ss"
    # Returns: 14:30:45

.EXAMPLE
    "2020-01-01", "2020-02-01" | Format-DateTime -Format "MMMM d, yyyy"
    # Returns: January 1, 2020 and February 1, 2020

.EXAMPLE
    Format-DateTime -Value (Get-Date) -Format "o" -Culture "en-US"
    # Returns: 2024-03-14T14:30:45.1234567-07:00
#>
function Format-DateTime {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [object]$Value,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Format,

        [Parameter()]
        [string]$Culture = [System.Globalization.CultureInfo]::CurrentCulture.Name
    )

    begin {
        # Create culture info object
        $cultureInfo = [System.Globalization.CultureInfo]::new($Culture)
    }

    process {
        try {
            # Convert string input to DateTime if necessary
            if ($Value -is [string]) {
                try {
                    $Value = [DateTime]::Parse($Value, $cultureInfo)
                }
                catch {
                    throw "Unable to parse the input date string: $_"
                }
            }
            elseif ($Value -isnot [DateTime]) {
                throw "Input must be a DateTime object or a string that can be parsed into a DateTime"
            }

            # Format the date
            $result = $Value.ToString($Format, $cultureInfo)
            return $result
        }
        catch {
            throw "Error formatting datetime: $_"
        }
    }
} 
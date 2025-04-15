<#
.SYNOPSIS
    JSON helper functions for PowerShell using System.Text.Json.

.DESCRIPTION
    A collection of JSON helper functions that provide common JSON operations with pipeline support.
    These functions use System.Text.Json for better performance and compatibility with modern .NET.

.NOTES
    These functions require PowerShell 7+ or .NET Core 3.0+ for System.Text.Json support.
#>

# Import required assembly
using namespace System.Text.Json

<#
.SYNOPSIS
    Converts an object to a JSON string.

.DESCRIPTION
    Serializes an object to a JSON string with optional formatting and indentation.

.PARAMETER InputObject
    The object to convert to JSON. Accepts pipeline input.

.PARAMETER Pretty
    If specified, the JSON output will be formatted with indentation.

.PARAMETER IndentSize
    The number of spaces to use for indentation when Pretty is specified.

.EXAMPLE
    @{name="John";age=30} | ConvertTo-JsonString
    # Returns: {"name":"John","age":30}

.EXAMPLE
    @{name="John";age=30} | ConvertTo-JsonString -Pretty
    # Returns formatted JSON with indentation
#>
function ConvertTo-JsonString {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$InputObject,

        [Parameter()]
        [switch]$Pretty,

        [Parameter()]
        [int]$IndentSize = 2
    )

    process {
        try {
            $options = [JsonSerializerOptions]::new()
            $options.WriteIndented = $Pretty
            $options.IndentSize = $IndentSize

            return [JsonSerializer]::Serialize($InputObject, $options)
        }
        catch {
            throw "Error converting to JSON: $_"
        }
    }
}

<#
.SYNOPSIS
    Converts a JSON string to an object.

.DESCRIPTION
    Deserializes a JSON string to a PowerShell object.

.PARAMETER JsonString
    The JSON string to convert. Accepts pipeline input.

.EXAMPLE
    '{"name":"John","age":30}' | ConvertFrom-JsonString
    # Returns: @{name=John; age=30}

.EXAMPLE
    Get-Content data.json | ConvertFrom-JsonString
    # Returns deserialized JSON from file
#>
function ConvertFrom-JsonString {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$JsonString
    )

    process {
        try {
            return [JsonSerializer]::Deserialize($JsonString, [object])
        }
        catch {
            throw "Error converting from JSON: $_"
        }
    }
}

<#
.SYNOPSIS
    Escapes special characters in a string for JSON.

.DESCRIPTION
    Escapes special characters in a string to make it safe for JSON serialization.

.PARAMETER InputString
    The string to escape. Accepts pipeline input.

.EXAMPLE
    "Hello, "World"" | ConvertTo-JsonEscape
    # Returns: Hello, \"World\"
#>
function ConvertTo-JsonEscape {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$InputString
    )

    process {
        try {
            $options = [JsonSerializerOptions]::new()
            $options.Encoder = [JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
            return [JsonSerializer]::Serialize($InputString, $options).Trim('"')
        }
        catch {
            throw "Error escaping JSON string: $_"
        }
    }
}

<#
.SYNOPSIS
    Converts an object to a JSON string and writes it to a file.

.DESCRIPTION
    Serializes an object to a JSON string and saves it to a file.

.PARAMETER InputObject
    The object to convert to JSON. Accepts pipeline input.

.PARAMETER Path
    The path to save the JSON file.

.PARAMETER Pretty
    If specified, the JSON output will be formatted with indentation.

.PARAMETER IndentSize
    The number of spaces to use for indentation when Pretty is specified.

.EXAMPLE
    @{name="John";age=30} | ConvertTo-JsonFile -Path "output.json" -Pretty
    # Saves formatted JSON to output.json
#>
function ConvertTo-JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [switch]$Pretty,

        [Parameter()]
        [int]$IndentSize = 2
    )

    process {
        try {
            $json = ConvertTo-JsonString -InputObject $InputObject -Pretty:$Pretty -IndentSize $IndentSize
            [System.IO.File]::WriteAllText($Path, $json)
        }
        catch {
            throw "Error saving JSON to file: $_"
        }
    }
}

<#
.SYNOPSIS
    Reads a JSON file and converts it to an object.

.DESCRIPTION
    Reads a JSON file and deserializes it to a PowerShell object.

.PARAMETER Path
    The path to the JSON file.

.EXAMPLE
    ConvertFrom-JsonFile -Path "data.json"
    # Returns deserialized JSON from file
#>
function ConvertFrom-JsonFile {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $json = [System.IO.File]::ReadAllText($Path)
        return ConvertFrom-JsonString -JsonString $json
    }
    catch {
        throw "Error reading JSON file: $_"
    }
} 
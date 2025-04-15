<#
.SYNOPSIS
    Converts a hashtable object into an ordered dictionary object.

.DESCRIPTION
    This function converts a hashtable into an ordered dictionary, with optional sorting of keys.
    It supports nested hashtables and provides better performance through direct .NET methods.

.PARAMETER HashTable
    The hashtable that needs to be converted.

.PARAMETER SortKeys
    If specified, the keys will be sorted alphabetically. Default is $false.

.PARAMETER Recursive
    If specified, nested hashtables will also be converted to ordered dictionaries. Default is $false.

.OUTPUTS
    System.Collections.Specialized.OrderedDictionary

.EXAMPLE
    $hash = @{ b = 2; a = 1; c = 3 }
    $ordered = ConvertTo-OrderedDict -HashTable $hash -SortKeys
#>
Function ConvertTo-OrderedDict {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    Param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [AllowEmptyCollection()]
        [ValidateNotNull()]
        [HashTable]$HashTable,

        [Parameter()]
        [switch]$SortKeys,

        [Parameter()]
        [switch]$Recursive
    )

    Process {
        try {
            # Create a new ordered dictionary
            $orderedDict = [System.Collections.Specialized.OrderedDictionary]::new()

            # Get the enumerator and optionally sort it
            $enumerator = if ($SortKeys) {
                $HashTable.GetEnumerator() | Sort-Object -Property Key
            } else {
                $HashTable.GetEnumerator()
            }

            # Process each key-value pair
            foreach ($item in $enumerator) {
                $value = if ($Recursive -and $item.Value -is [hashtable]) {
                    ConvertTo-OrderedDict -HashTable $item.Value -SortKeys:$SortKeys -Recursive
                } else {
                    $item.Value
                }
                
                $orderedDict.Add($item.Key, $value)
            }

            return $orderedDict
        }
        catch {
            Write-Error "Failed to convert hashtable to ordered dictionary: $_"
            throw
        }
    }
}

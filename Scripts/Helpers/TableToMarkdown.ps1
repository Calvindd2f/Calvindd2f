<#

  .DESCRIPTION

  This function Gets a list of PSObjects and convert it to a markdown table


  .PARAMETER collection

  The list of PSObjects that will should be converted to markdown format


  .PARAMETER name

  The name of the markdown table. when given this name will be the title of the table


  .OUTPUTS

  The markdown table string representation

  #>

Function TableToMarkdown {
    [Alias("ConvertTo-MarkdownTable")]
    [CmdletBinding()]
    [OutputType([string])]
    Param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [AllowEmptyCollection()]
        [Object]$collection,

        [Parameter(Mandatory = $false, Position = 1)]
        [String]$name
    )
    Begin {
        # Initializing $result
        $result = ''
        if ($name) {
            $result += "### $name`n"
        }
        # Initializing $items
        $items = @()
        # Initializing $headers
        $headers = @()
    }

    Process {
        # proccessing items and headers
        ForEach ($item in $collection) {
            if ($item -Is [HashTable]) {
                # Need to convert hashtables to ordered dicts so that the keys/values will be in the same order
                $item = $item | ConvertTo-OrderedDict
            }
            elseif ($item -Is [PsCustomObject]) {
                $newItem = @{}
                $item.PSObject.Properties | ForEach-Object { $newItem[$_.Name] = $_.Value }
                $item = $newItem | ConvertTo-OrderedDict
            }
            $items += $item
        }
    }
    End {
        if ($items) {
            if ($items[0] -is [System.Collections.IDictionary]) {
                $headers = $items[0].keys
            }
            else {
                $headers = $item[0].PSObject.Properties | ForEach-Object { $_.Name }
            }
            # Writing the headers line
            $result += '| ' + ($headers -join ' | ')
            $result += "`n"

            # Writing the separator line
            $separator = @()
            ForEach ($key in $headers) {
                $separator += '---'
            }
            $result += '| ' + ($separator -join ' | ')
            $result += "`n"

            # Writing the values
            ForEach ($item in $items) {
                $values = @()
                if ($items[0] -is [System.Collections.IDictionary]) {
                    $raw_values = $item.values
                }
                else {
                    $raw_values = $item[0].PSObject.Properties | ForEach-Object { $_.Value }
                }
                foreach ($raw_value in $raw_values) {
                    if ($null -ne $raw_value) {
                        try {
                            <# PWSH Type Code of numbers are 5 to 15. So we will handle them with ToString
                              and the rest are Json Serializble #>
                            $typeValue = $raw_value.getTypeCode().value__
                            $is_number = ($typeValue -ge 5 -and $typeValue -le 15)
                        }
                        catch { $is_number = $false }

                        if ($raw_value -is [string] -or $is_number) {
                            $value = $raw_value.ToString()
                        }
                        else {
                            $value = $raw_value | ConvertTo-Json -Compress -Depth 5
                        }
                    }
                    else {
                        $value = ""
                    }
                    $values += $value | stringEscapeMD
                }
                $result += '| ' + ($values -join ' | ')
                $result += "`n"
            }
        }
        else {
            $result += "**No entries.**`n"
        }
        return $result
    }
}
<#

  .DESCRIPTION

  This function Gets a string and escape all special characters in it so that it can be in correct markdown format


  .PARAMETER data

  The string that needs to be escaped


  .OUTPUTS

  A string in which all special characters are escaped

  #>

Function stringEscapeMD() {
    [OutputType([string])]
    Param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [String]$data
    )
    begin {
        $markdown_chars = @('\', '`', '*', '_', '{', '}', '[', ']', '(', ')', '#', '+', '-', '|', '!')
    }
    process {
        $result = $data.Replace("`r`n", "<br>").Replace("`r", "<br>").Replace("`n", "<br>")
        foreach ($char in $markdown_chars) {
            $result = $result.Replace("$char", "\$char")
        }
        $result
    }
}
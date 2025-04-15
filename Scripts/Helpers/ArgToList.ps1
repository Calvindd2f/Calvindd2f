# -----------------------------------------------------------------------

# Utility Functions

# -----------------------------------------------------------------------


<#

  .DESCRIPTION

  Converts a string representation of args to a list


  .PARAMETER Arg

  The argument to convert


  .PARAMETER Seperator

  The seperator to use (default ',')


  .OUTPUTS

  Object[]. Returns an array of the arguments

  #>

function ArgToList($Arg, [string]$Seperator = ",") {
    if (! $Arg) {
        $r = @()
    }
    elseif ($Arg.GetType().IsArray) {
        $r = $Arg
    }
    elseif ($Arg[0] -eq "[" -and $Arg[-1] -eq "]") {
        # json string
        $r = $Arg | ConvertFrom-Json -AsHashtable
    }
    else {
        $r = $Arg.Split($Seperator)
    }
    # we want to return an array and avoid one-at-a-time processing
    # see: https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_return?view=powershell-6#return-values-and-the-pipeline
    return @(, $r)
}

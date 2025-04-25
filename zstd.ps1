# pzstd
# function to tar & compress using zstd a single file/folder or an array of files/folders
# Uses .NET to compress the files/folders
# Overall uses .NET methods and classes along with zstd & WIN API to compress the files/folders

function Compress-Zstd {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $false)]
        [string]$OutputPath = "$Path.zstd",
        [Parameter(Mandatory = $false)]
        [int]$CompressionLevel = 3,
        [Parameter(Mandatory = $false)]
        [switch]$Tar,
        [Parameter(Mandatory = $false)]
        [switch]$DeleteSource
    )

    # Check if the path exists  
    if (-not (Test-Path $Path)) {
        Write-Error "The path $Path does not exist"
        return
    }

    # Check if the output path exists
    if (-not (Test-Path $OutputPath)) {
        Write-Error "The output path $OutputPath does not exist"
        return
    }

    # Check if the compression level is valid
    if ($CompressionLevel -lt 1 -or $CompressionLevel -gt 12) {
        Write-Error "The compression level must be between 1 and 12"
        return
    }

    # Check if the path is a file or folder
    if (-not (Test-Path $Path -PathType Container)) {
        Write-Error "The path $Path is not a file or folder"
        return
    }

    
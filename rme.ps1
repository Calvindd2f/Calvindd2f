<#
    .SYNOPSIS
    Removes Office installations and optionally reinstalls them (64-bit or 32-bit).
    .DESCRIPTION
    The script removes any existing Office installations using the SaRACMD tool, 
    and based on parameters, optionally reinstalls Office either in 64-bit or 32-bit mode. 
    It handles download retries, process killing, and clean reinstalls.
    .PARAMETER Reinstall64
    Reinstalls 64-bit Office after removal.
    .PARAMETER Reinstall32
    Reinstalls 32-bit Office after removal.
    .PARAMETER noreinstall
    Removes Office without reinstalling.
    .OUTPUTS
    Activity output object with success, debug, error, and output information.
    .EXAMPLE
    PS> rmOffice -Reinstall64
    Removes Office and reinstalls 64-bit Office.
#>

[CmdletBinding()]
param(
    [switch]$Reinstall64,
    [switch]$Reinstall32,
    [switch]$noreinstall
)

# Read-only variables declaration (All-Man style)
<#
  read_only
  ####################################################
  ########## INPUT
  ####################################################
  $Reinstall64 = "Reinstall 64-bit Office"
  $Reinstall32 = "Reinstall 32-bit Office"
  $noreinstall = "Do not reinstall Office"
  ####################################################
  ########## OUTPUT
  ####################################################
  $activityOutput = "Activity object containing status, debug, error, and output"
  ####################################################
#>

$activityOutput = [pscustomobject]@{
    success = $true
    debug   = $null
    error   = $null
    output  = $null
}

$zipPath = Join-Path -Path $env:HOMEDRIVE -ChildPath "SaRACMD.zip"
$downloadUrl = "https://aka.ms/SaRA_EnterpriseVersionFiles"
$O365setup64 = "C:\Users\OfficeSetup64.exe"
$O365setup32 = "C:\Users\OfficeSetup32.exe"
$O365Url64 = "https://c2rsetup.officeapps.live.com/c2r/download.aspx?productReleaseID=O365ProPlusRetail&platform=X64&language=en-us"
$O365Url32 = "https://c2rsetup.officeapps.live.com/c2r/download.aspx?productReleaseID=O365ProPlusRetail&platform=X86&language=en-us"
$retry = 3
$timeout = 30
$killIfinvokefails = @("lync", "winword", "excel", "msaccess", "mstore", "infopath", "setlang", "msouc", "ois", "onenote", "outlook", "powerpnt", "mspub", "groove", "visio", "winproj", "graph", "teams")

# Verify-Activity: Ensures preconditions and environment are ready for execution
function Verify-Activity {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $activityOutput = [pscustomobject]@{
        success = $true
        debug   = $null
        error   = $null
        output  = $null
    }
    
    if (!(Test-Path $env:HOMEDRIVE)) {
        $activityOutput.success = $false
        $activityOutput.error = "Home drive path not found."
        return $activityOutput
    }

    return $activityOutput
}

# Main-Activity: Downloads and extracts the SaRACMD tool, removes Office installations
function Main-Activity {
    param(
        [string]$downloadUrl,
        [string]$zipPath,
        [int]$retry,
        [int]$timeout,
        [array]$killIfinvokefails
    )

    $activityOutput = [pscustomobject]@{
        success = $true
        debug   = $null
        error   = $null
        output  = $null
    }

    # Download SaRACMD
    [console]::WriteLine("Downloading SaRACMD tool...")
    $attempt = 0
    while ($attempt -lt $retry) {
        try {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath
            Expand-Archive $zipPath -DestinationPath $env:windir -ErrorAction Continue
            if (!(Get-Command -Name Expand-Archive -ErrorAction SilentlyContinue)) {
                [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $env:windir)
            }
            break
        } catch {
            Write-Warning "Attempt $($attempt+1) failed. Error: $_"
            $attempt++
            if ($attempt -eq $retry) {
                $activityOutput.success = $false
                $activityOutput.error = "Failed to download SaRACMD after $retry attempts."
                return $activityOutput
            }
            Start-Sleep -Seconds $timeout
        }
    }

    # Invoke SaRACMD to remove Office
    try {
        & "$env:windir\SaRACMD.exe" -S OfficeScrubScenario -AcceptEula -OfficeVersion All
    } catch {
        Write-Warning "Execution failed. Stopping running Office processes..."
        $killIfinvokefails | ForEach-Object {
            Get-Process $_ -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        $activityOutput.success = $false
        $activityOutput.error = "Failed to execute SaRACMD. Error: $_"
        return $activityOutput
    }

    return $activityOutput
}

# Execute-Activity: Coordinates verification, download, execution, and optional reinstall
function Execute-Activity {
    param (
        [switch]$Reinstall64,
        [switch]$Reinstall32,
        [switch]$noreinstall
    )

    # Step 1: Verification
    $verificationResult = Verify-Activity
    if (-not $verificationResult.success) {
        Write-Host "Verification failed: $($verificationResult.error)"
        return $verificationResult
    }

    # Step 2: Removal and Download
    $mainResult = Main-Activity -downloadUrl $downloadUrl -zipPath $zipPath -retry $retry -timeout $timeout -killIfinvokefails $killIfinvokefails
    if (-not $mainResult.success) {
        Write-Host "Main activity failed: $($mainResult.error)"
        return $mainResult
    }

    # Step 3: Reinstallation (if specified)
    if ($Reinstall64) {
        [console]::WriteLine("Reinstalling 64-bit Office...")
        Invoke-WebRequest -Uri $O365Url64 -OutFile $O365setup64
        Start-Process -FilePath $O365setup64 -Wait
    } elseif ($Reinstall32) {
        [console]::WriteLine("Reinstalling 32-bit Office...")
        Invoke-WebRequest -Uri $O365Url32 -OutFile $O365setup32
        Start-Process -FilePath $O365setup32 -Wait
    } elseif ($noreinstall) {
        [console]::WriteLine("Office removal complete. No reinstallation specified.")
    }

    return $mainResult
}

# Run the script
$finalResult = Execute-Activity -Reinstall64:$Reinstall64 -Reinstall32:$Reinstall32 -noreinstall:$noreinstall
return $finalResult

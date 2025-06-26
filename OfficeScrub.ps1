<#
.SYNOPSIS
Removes Office installations and optionally reinstalls them (64-bit or 32-bit).

.DESCRIPTION
Removes existing Office installations using SaRACMD tool and optionally reinstalls Office.

.PARAMETER Reinstall64
Reinstalls 64-bit Office after removal.

.PARAMETER Reinstall32
Reinstalls 32-bit Office after removal.

.PARAMETER NoReinstall
Removes Office without reinstalling.

.EXAMPLE
Remove-Office -Reinstall64

.NOTES
Author: Calvindd2f
Version: 2.0.0
Date: 2025-06-26

#>

[CmdletBinding()]
param(
    [switch]$Reinstall64,
    [switch]$Reinstall32,
    [switch]$NoReinstall
)

# Configuration
$Config = @{
    SaRAUrl         = "https://aka.ms/SaRA_EnterpriseVersionFiles"
    SaRAPath        = "$env:TEMP\SaRACMD.zip"
    SaRAExe         = "$env:TEMP\SaRACMD.exe"
    Office64Url     = "https://c2rsetup.officeapps.live.com/c2r/download.aspx?productReleaseID=O365ProPlusRetail&platform=X64&language=en-us"
    Office32Url     = "https://c2rsetup.officeapps.live.com/c2r/download.aspx?productReleaseID=O365ProPlusRetail&platform=X86&language=en-us"
    Office64Setup   = "$env:TEMP\OfficeSetup64.exe"
    Office32Setup   = "$env:TEMP\OfficeSetup32.exe"
    RetryCount      = 3
    RetryDelay      = 30
    OfficeProcesses = @("lync", "winword", "excel", "msaccess", "mstore", "infopath", "setlang", "msouc", "ois", "onenote", "outlook", "powerpnt", "mspub", "groove", "visio", "winproj", "graph", "teams")
}

function New-ActivityResult {
    param([bool]$Success = $true, [string]$Error = $null, [string]$Output = $null)
    
    [PSCustomObject]@{
        Success   = $Success
        Error     = $Error
        Output    = $Output
        Timestamp = Get-Date
    }
}

function Stop-OfficeProcesses {
    Write-Verbose "Stopping Office processes..."
    $Config.OfficeProcesses | ForEach-Object {
        Get-Process $_ -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

function Install-SaRATool {
    Write-Host "Downloading SaRA tool..." -ForegroundColor Yellow
    
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    for ($attempt = 1; $attempt -le $Config.RetryCount; $attempt++) {
        try {
            Invoke-WebRequest -Uri $Config.SaRAUrl -OutFile $Config.SaRAPath -UseBasicParsing
            Expand-Archive $Config.SaRAPath -DestinationPath $env:windir -Force
            
            if (Test-Path $Config.SaRAExe) {
                Write-Host "SaRA tool downloaded successfully" -ForegroundColor Green
                return New-ActivityResult -Success $true
            }
        }
        catch {
            Write-Warning "Download attempt $attempt failed: $($_.Exception.Message)"
            if ($attempt -lt $Config.RetryCount) {
                Start-Sleep -Seconds $Config.RetryDelay
            }
        }
    }
    
    return New-ActivityResult -Success $false -Error "Failed to download SaRA tool after $($Config.RetryCount) attempts"
}

function Remove-OfficeInstallation {
    Write-Host "Removing Office installation..." -ForegroundColor Yellow
    
    try {
        $process = Start-Process -FilePath $Config.SaRAExe -ArgumentList "-S", "OfficeScrubScenario", "-AcceptEula", "-OfficeVersion", "All" -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Office removal completed successfully" -ForegroundColor Green
            return New-ActivityResult -Success $true
        }
        else {
            throw "SaRA tool exited with code $($process.ExitCode)"
        }
    }
    catch {
        Write-Warning "Office removal failed: $($_.Exception.Message)"
        Stop-OfficeProcesses
        return New-ActivityResult -Success $false -Error $_.Exception.Message
    }
}

function Install-Office {
    param([string]$Architecture)
    
    $url = if ($Architecture -eq "64") { $Config.Office64Url } else { $Config.Office32Url }
    $setupPath = if ($Architecture -eq "64") { $Config.Office64Setup } else { $Config.Office32Setup }
    
    Write-Host "Installing Office $Architecture-bit..." -ForegroundColor Yellow
    
    try {
        Invoke-WebRequest -Uri $url -OutFile $setupPath -UseBasicParsing
        Start-Process -FilePath $setupPath -Wait
        Write-Host "Office $Architecture-bit installation completed" -ForegroundColor Green
        return New-ActivityResult -Success $true
    }
    catch {
        return New-ActivityResult -Success $false -Error "Failed to install Office $Architecture-bit: $($_.Exception.Message)"
    }
}

function Invoke-FallbackRemoval {
    Write-Host "Attempting fallback Office removal..." -ForegroundColor Yellow
    
    $vbsScript = "$env:TEMP\OfficeScrub.vbs"
    if (Test-Path $vbsScript) {
        Start-Process -FilePath $vbsScript -Wait
        return $true
    }
    
    try {
        $tempVbs = "$env:TEMP\OffScrubc2r.vbs"
        Invoke-RestMethod "https://raw.githubusercontent.com/Calvindd2f/Calvindd2f/refs/heads/main/OffScrubc2r.vbs" -OutFile $tempVbs
        Start-Process -FilePath $tempVbs -Wait
        Remove-Item $tempVbs -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        Write-Warning "Fallback removal failed: $($_.Exception.Message)"
        return $false
    }
}

# Main execution
try {
    if ((@($Reinstall64, $Reinstall32, $NoReinstall) | Where-Object { $_ }).Count -gt 1) {
        throw "Only one parameter can be specified at a time"
    }
    
    # Primary removal attempt
    $saraResult = Install-SaRATool
    if ($saraResult.Success) {
        $removeResult = Remove-OfficeInstallation
        if (-not $removeResult.Success) { throw $removeResult.Error }
    }
    else {
        if (-not (Invoke-FallbackRemoval)) { throw "All removal methods failed" }
    }
    
    # Reinstall if requested
    switch ($true) {
        $Reinstall64 { 
            $result = Install-Office -Architecture "64"
            if (-not $result.Success) { throw $result.Error }
        }
        $Reinstall32 { 
            $result = Install-Office -Architecture "32"
            if (-not $result.Success) { throw $result.Error }
        }
        default { Write-Host "Office removal completed. No reinstallation requested." -ForegroundColor Green }
    }
    
    New-ActivityResult -Success $true -Output "Operation completed successfully"
}
catch {
    Write-Error $_.Exception.Message
    New-ActivityResult -Success $false -Error $_.Exception.Message
}
finally {
    @($Config.SaRAPath, $Config.Office64Setup, $Config.Office32Setup) | Remove-Item -ErrorAction SilentlyContinue
    [System.GC]::Collect();
}
Exit 0

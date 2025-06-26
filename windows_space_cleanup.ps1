#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Comprehensive disk cleanup script for Datto RMM deployment
.DESCRIPTION
    Clears caches, temp files, GUID folders, and other unnecessary data for all user profiles
    Optionally removes old files from Downloads and Documents folders (1+ years old)
    Removes GUID-named temporary folders from user profiles
    Enhanced temp folder cleanup across all AppData locations
    Tracks space savings and provides detailed reporting
.NOTES
    Designed for Datto RMM - returns exit codes and structured output
    Configure $CleanOldDownloads and $FileAgeThresholdDays variables to control old file cleanup
    Protected file extensions (.exe, .msi, etc.) are preserved regardless of age
    GUID folders containing critical files (.exe, .dll, .sys, .msi) are preserved
    Author: System Administrator
    Version: 1.2
#>

# Initialize variables
$TotalSpaceFreed = 0
$CleanupReport = @()
$ErrorLog = @()

# Configuration
$CleanOldDownloads = $true  # Set to $false to disable old file cleanup
$FileAgeThresholdDays = 365  # Files older than this will be deleted (1 year)
$ProtectedExtensions = @('.exe', '.msi', '.dmg', '.iso', '.vhd', '.vhdx', '.ova', '.ovf')  # Files to preserve regardless of age

# Function to get folder size safely

# Define structured class for cleanup entries
class CleanupEntry {
    [string]$Location
    [string]$Path
    [string]$SpaceFreed
    [string]$Status

    CleanupEntry([string]$location, [string]$path, [string]$spaceFreed, [string]$status) {
        $this.Location = $location
        $this.Path = $path
        $this.SpaceFreed = $spaceFreed
        $this.Status = $status
    }
}

function Get-FolderSize {
    param([string]$Path)
    try {
        if ([string]::IsNullOrEmpty($Path) -or -not (Test-Path $Path)) {
            return 0
        }

        $files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue
        if ($null -eq $files) {
            return 0
        }

        $measurement = $files | Measure-Object -Property Length -Sum
        if ($null -eq $measurement -or $null -eq $measurement.Sum) {
            return 0
        }

        return [math]::Round($measurement.Sum / 1MB, 2)
    }
    catch {
        Write-Verbose "Error getting folder size for $Path : $($_.Exception.Message)"
        return 0
    }
}

# Function to clean directory safely
function Remove-DirectoryContents {
    param(
        [string]$Path,
        [string]$Description
    )

    try {
        if ([string]::IsNullOrEmpty($Path) -or -not (Test-Path $Path)) {
            return
        }

        $sizeBefore = Get-FolderSize -Path $Path

        # Remove files first, then empty directories - with better error handling
        $files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue
        if ($null -ne $files) {
            foreach ($file in $files) {
                try {
                    if ($null -ne $file -and (Test-Path $file.FullName)) {
                        Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
                    }
                }
                catch {
                    # Continue processing other files even if one fails
                    continue
                }
            }
        }

        # Remove empty directories
        $directories = Get-ChildItem -Path $Path -Recurse -Directory -ErrorAction SilentlyContinue
        if ($null -ne $directories) {
            $sortedDirs = $directories | Sort-Object FullName -Descending
            foreach ($dir in $sortedDirs) {
                try {
                    if ($null -ne $dir -and (Test-Path $dir.FullName)) {
                        Remove-Item -Path $dir.FullName -Force -Recurse -ErrorAction SilentlyContinue
                    }
                }
                catch {
                    # Continue processing other directories even if one fails
                    continue
                }
            }
        }

        $sizeAfter = Get-FolderSize -Path $Path
        $spaceFreed = $sizeBefore - $sizeAfter

        if ($spaceFreed -gt 0) {
            $script:TotalSpaceFreed = New-Object System.Collections.ArrayList
            $null = $script:TotalSpaceFreed.Add($spaceFreed)
            $script:CleanupReport = New-Object System.Collections.ArrayList
            $null = $script:CleanupReport.Add([PSCustomObject]@{
                Location   = $Description
                Path       = $Path
                SpaceFreed = "$spaceFreed MB"
                Status     = "Success"
            })
            Write-Host "✓ $Description`: $spaceFreed MB freed" -ForegroundColor Green
        }
    }
    catch {
        $script:ErrorLog = New-Object System.Collections.ArrayList
        $null = $script:ErrorLog.Add("Error cleaning $Description ($Path): $($_.Exception.Message)")
        Write-Warning "Error cleaning $Description : $($_.Exception.Message)"
    }
    New-Object CleanupEntry -ArgumentList $Description, $Path, "$spaceFreed MB", "Success"
    return
}

$browserPaths = @{
    "Chrome Cache"  = "$UserProfile\AppData\Local\Google\Chrome\User Data\Default\Cache"
    "Chrome Cache2" = "$UserProfile\AppData\Local\Google\Chrome\User Data\Default\Cache2"
    "Edge Cache"    = "$UserProfile\AppData\Local\Microsoft\Edge\User Data\Default\Cache"
    "Firefox Cache" = "$UserProfile\AppData\Local\Mozilla\Firefox\Profiles\*\cache2"
    "IE Cache"      = "$UserProfile\AppData\Local\Microsoft\Windows\INetCache"
    "IE Cookies"    = "$UserProfile\AppData\Local\Microsoft\Windows\INetCookies"
}

foreach ($browser in $browserPaths.GetEnumerator()) {
    try {
        if ([string]::IsNullOrEmpty($browser.Value)) { continue }

        $paths = Get-ChildItem -Path $browser.Value -ErrorAction SilentlyContinue
        if ($null -ne $paths) {
            foreach ($path in $paths) {
                if ($null -ne $path -and $null -ne $path.FullName) {
                    Remove-DirectoryContents -Path $path.FullName -Description "$($browser.Key) - $Username"
                }
            }
        }
    }
    catch {
        $null = $script:ErrorLog.Add("Error processing browser cache $($browser.Key) for $Username : $($_.Exception.Message)")
        continue
    }
}


# Function to clean GUID-named folders from user profiles
function Remove-GuidFolders {
    param([string]$UserProfile, [string]$Username)

    if ([string]::IsNullOrEmpty($UserProfile) -or [string]::IsNullOrEmpty($Username)) {
        return
    }

    # GUID pattern: 8-4-4-4-12 hex digits
    $guidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

    # Get all GUID-named folders in user profile
    $guidFolders = Get-ChildItem -Path $UserProfile -Recurse -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match $guidPattern }

    function Remove-OldUserFiles {
        param([string]$UserProfile, [string]$Username)

        if (-not $CleanOldDownloads -or [string]::IsNullOrEmpty($UserProfile) -or [string]::IsNullOrEmpty($Username)) {
            if (-not $CleanOldDownloads) {
                Write-Host "  Old file cleanup disabled - skipping Downloads/Documents" -ForegroundColor Gray
            }
            return
        }

        $cutoffDate = (Get-Date).AddDays(-$FileAgeThresholdDays)
        $foldersToClean = @{
            "Downloads" = "$UserProfile\Downloads"
            "Documents" = "$UserProfile\Documents"
        }

        foreach ($folder in $foldersToClean.GetEnumerator()) {
            try {
                $folderPath = $folder.Value
                if ([string]::IsNullOrEmpty($folderPath) -or -not (Test-Path $folderPath)) {
                    continue
                }

                Write-Host "  Scanning $($folder.Key) for files older than $FileAgeThresholdDays days..." -ForegroundColor Yellow

                $allFiles = Get-ChildItem -Path $folderPath -File -Recurse -ErrorAction SilentlyContinue
                if ($null -eq $allFiles) {
                    Write-Host "    No files found in $($folder.Key)" -ForegroundColor Gray
                    continue
                }

                $oldFiles = @()
                foreach ($file in $allFiles) {
                    try {
                        if ($null -ne $file -and
                            $null -ne $file.LastWriteTime -and
                            $null -ne $file.Extension -and
                            $file.LastWriteTime -lt $cutoffDate -and
                            $file.Extension -notin $ProtectedExtensions) {
                            $oldFiles = New-Object System.Collections.ArrayList
                            $null = $oldFiles.Add($file)
                        }
                    }
                    catch {
                        # Skip files that cannot be accessed
                        continue
                    }
                }

                if ($oldFiles.Count -eq 0) {
                    Write-Host "    No old files found in $($folder.Key)" -ForegroundColor Gray
                    continue
                }

                $sizeBefore = 0
                foreach ($file in $oldFiles) {
                    if ($null -ne $file -and $null -ne $file.Length) {
                        $sizeBefore = New-Object System.Collections.ArrayList
                        $null = $sizeBefore.Add($file.Length)
                    }
                }
                $sizeBeforeMB = [math]::Round($sizeBefore / 1MB, 2)

                $deletedCount = 0
                foreach ($file in $oldFiles) {
                    try {
                        if ($null -ne $file -and $null -ne $file.FullName -and (Test-Path $file.FullName)) {
                            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                            $deletedCount++
                        }
                    }
                    catch {
                        $null = $script:ErrorLog.Add("Error deleting old file $($file.FullName): $($_.Exception.Message)")
                        continue
                    }
                }

                if ($deletedCount -gt 0) {
                    $null = $script:TotalSpaceFreed.Add($sizeBeforeMB)
                    $null = $script:CleanupReport.Add([PSCustomObject]@{
                        Location   = "$($folder.Key) Old Files - $Username"
                        Path       = $folderPath
                        SpaceFreed = "$sizeBeforeMB MB"
                        Status     = "Success - $deletedCount files deleted"
                    })
                    Write-Host "    ✓ $($folder.Key): $deletedCount old files deleted, $sizeBeforeMB MB freed" -ForegroundColor Green
                }
            }
            catch {
                $null = $script:ErrorLog.Add("Error processing old files in $($folder.Key) for $Username : $($_.Exception.Message)")
                Write-Warning "  Error processing old files in $($folder.Key): $($_.Exception.Message)"
            }
        }
    }
    New-Object CleanupEntry -ArgumentList $($folder.Key) Old Files - $Username, $folderPath, "$sizeBeforeMB MB", "Success - $deletedCount files deleted"
    $UserProfiles = Get-WmiObject -Class Win32_UserProfile |
    Where-Object {
        $null -ne $_ -and
        $_.Special -eq $false -and
        $null -ne $_.LocalPath -and
        $_.LocalPath -notlike "*\Windows\*" -and
        $_.LocalPath -ne ""
    }

    if ($null -eq $UserProfiles) {
        Write-Warning "No user profiles found to process"
        $UserProfiles = @()
    }

    Write-Host "Found $($UserProfiles.Count) user profiles to process" -ForegroundColor Yellow
}
catch {
    Write-Error "Failed to enumerate user profiles: $($_.Exception.Message)"
    exit 1
}

# Clean each user profile
foreach ($Profile in $UserProfiles) {
    try {
        if ($null -eq $Profile -or $null -eq $Profile.LocalPath) {
            continue
        }

        $UserPath = $Profile.LocalPath
        if ([string]::IsNullOrEmpty($UserPath) -or -not (Test-Path $UserPath)) {
            Write-Warning "Skipping invalid user profile path: $UserPath"
            continue
        }

        $Username = Split-Path $UserPath -Leaf
        if ([string]::IsNullOrEmpty($Username)) {
            Write-Warning "Skipping profile with empty username: $UserPath"
            continue
        }

        Write-Host "`nProcessing user: $Username" -ForegroundColor Cyan

        # User-specific temp and cache locations - Enhanced temp cleanup
        $userCleanupPaths = @{
            "User Temp - $Username"               = "$UserPath\AppData\Local\Temp"
            "User Temp2 - $Username"              = "$UserPath\AppData\Local\Tmp"
            "User Temp Roaming - $Username"       = "$UserPath\AppData\Roaming\Temp"
            "User Temp LocalLow - $Username"      = "$UserPath\AppData\LocalLow\Temp"
            "Recent Items - $Username"            = "$UserPath\AppData\Roaming\Microsoft\Windows\Recent"
            "Thumbnail Cache - $Username"         = "$UserPath\AppData\Local\Microsoft\Windows\Explorer"
            "Windows Error Reports - $Username"   = "$UserPath\AppData\Local\Microsoft\Windows\WER"
            "CrashDumps - $Username"              = "$UserPath\AppData\Local\CrashDumps"
            "Adobe Cache - $Username"             = "$UserPath\AppData\Local\Adobe\*\Cache"
            "Teams Cache - $Username"             = "$UserPath\AppData\Roaming\Microsoft\Teams\tmp"
            "Teams Cache2 - $Username"            = "$UserPath\AppData\Roaming\Microsoft\Teams\Cache"
            "Skype Cache - $Username"             = "$UserPath\AppData\Roaming\Skype\*\chatsync"
            "Discord Cache - $Username"           = "$UserPath\AppData\Roaming\discord\Cache"
            "Spotify Cache - $Username"           = "$UserPath\AppData\Local\Spotify\Storage"
            "Steam Logs - $Username"              = "$UserPath\AppData\Local\Steam\logs"
            "Windows Installer Cache - $Username" = "$UserPath\AppData\Local\Microsoft\Windows\INetCache\IE"
            "Office Cache - $Username"            = "$UserPath\AppData\Local\Microsoft\Office\*\OfficeFileCache"
            "OneDrive Temp - $Username"           = "$UserPath\AppData\Local\Microsoft\OneDrive\logs"
        }

        # Clean user-specific locations
        foreach ($location in $userCleanupPaths.GetEnumerator()) {
            try {
                if ([string]::IsNullOrEmpty($location.Value)) { continue }

                $paths = Get-ChildItem -Path $location.Value -ErrorAction SilentlyContinue
                if ($null -ne $paths) {
                    foreach ($path in $paths) {
                        if ($null -ne $path -and $null -ne $path.FullName) {
                            Remove-DirectoryContents -Path $path.FullName -Description $location.Key
                        }
                    }
                }
            }
            catch {
                $null = $script:ErrorLog.Add("Error processing location $($location.Key): $($_.Exception.Message)")
                continue
            }
        }

        # Clean browser caches
        Clear-BrowserCaches -UserProfile $UserPath -Username $Username

        # Clean GUID-named folders
        Remove-GuidFolders -UserProfile $UserPath -Username $Username

        # Clean old files from Downloads and Documents
        Remove-OldUserFiles -UserProfile $UserPath -Username $Username

    }
    catch {
        $ErrorLog = New-Object System.Collections.ArrayList
        $null = $ErrorLog.Add("Error processing user $Username : $($_.Exception.Message)")
        Write-Warning "Error processing user $Username : $($_.Exception.Message)"
    }
}

Write-Host "`nCleaning system-wide locations..." -ForegroundColor Cyan

# System-wide cleanup locations
$systemCleanupPaths = @{
    "Windows Temp"          = "$env:WINDIR\Temp"
    "System Temp"           = "$env:TEMP"
    "System32 Temp"         = "$env:WINDIR\System32\config\systemprofile\AppData\Local\Temp"
    "Prefetch"              = "$env:WINDIR\Prefetch"
    "Software Distribution" = "$env:WINDIR\SoftwareDistribution\Download"
    "CBS Logs"              = "$env:WINDIR\Logs\CBS"
    "DISM Logs"             = "$env:WINDIR\Logs\DISM"
    "Windows Update Logs"   = "$env:WINDIR\WindowsUpdate.log*"
    "Memory Dumps"          = "$env:WINDIR\Minidump"
    "Error Reports"         = "$env:ALLUSERSPROFILE\Microsoft\Windows\WER"
    "Delivery Optimization" = "$env:WINDIR\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Logs"
    "IIS Logs"              = "$env:WINDIR\System32\LogFiles\W3SVC*"
    "Event Trace Logs"      = "$env:WINDIR\System32\LogFiles\WMI"
}

foreach ($location in $systemCleanupPaths.GetEnumerator()) {
    Remove-DirectoryContents -Path $location.Value -Description $location.Key
}

# Clean Recycle Bin
Write-Host "`nEmptying Recycle Bin..." -ForegroundColor Yellow
try {
    $sizeBefore = 0
    $recycleBins = Get-ChildItem -Path "C:\`$Recycle.Bin" -Directory -ErrorAction SilentlyContinue

    if ($null -ne $recycleBins) {
        foreach ($bin in $recycleBins) {
            if ($null -ne $bin -and $null -ne $bin.FullName) {
                $null = $sizeBefore.Add((Get-FolderSize -Path $bin.FullName))
            }
        }
    }

    # Empty recycle bin using Shell.Application with better error handling
    $shell = $null
    $recycleBin = $null
    try {
        $shell = New-Object -ComObject Shell.Application
        if ($null -ne $shell) {
            $recycleBin = $shell.Namespace(0xA)
            if ($null -ne $recycleBin) {
                $items = $recycleBin.Items()
                if ($null -ne $items) {
                    foreach ($item in $items) {
                        try {
                            if ($null -ne $item) {
                                $item.InvokeVerb("delete")
                            }
                        }
                        catch {
                            # Continue with other items if one fails
                            continue
                        }
                    }
                }
            }
        }
    }
    finally {
        # Clean up COM objects
        if ($null -ne $recycleBin) {
            [void][System.Runtime.Interopservices.Marshal]::ReleaseComObject($recycleBin)
        }
        if ($null -ne $shell) {
            [void][System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell)
        }
    }

    if ($sizeBefore -gt 0) {
        $CleanupReport = New-Object System.Collections.ArrayList
        $null = $CleanupReport.Add([PSCustomObject]@{
            Location   = "Recycle Bin"
            Path       = "C:\`$Recycle.Bin"
            SpaceFreed = "$sizeBefore MB"
            Status     = "Success"
        })
        $TotalSpaceFreed = New-Object System.Collections.ArrayList
        $null = $TotalSpaceFreed.Add($sizeBefore)
        Write-Host "✓ Recycle Bin: $sizeBefore MB freed" -ForegroundColor Green
    }
}
catch {
    $null = $ErrorLog.Add("Error emptying Recycle Bin: $($_.Exception.Message)")
    Write-Warning "Error emptying Recycle Bin: $($_.Exception.Message)"
}
New-Object CleanupEntry -ArgumentList Recycle Bin, C:\`$Recycle.Bin, "$sizeBefore MB", "Success"
Start-Sleep -Seconds 5
$cleanupAfter = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq "C:" } | Select-Object -ExpandProperty FreeSpace
$cleanupFreed = [math]::Round(($cleanupAfter - $cleanupBefore) / 1MB, 2)

if ($cleanupFreed -gt 0) {
    $null = $TotalSpaceFreed.Add($cleanupFreed)
    $null = $CleanupReport.Add([PSCustomObject]@{
        Location   = "Windows Disk Cleanup"
        Path       = "System Utility"
        SpaceFreed = "$cleanupFreed MB"
        Status     = "Success"
    })
    Write-Host "✓ Windows Disk Cleanup: $cleanupFreed MB freed" -ForegroundColor Green
}

catch {
    $null = $ErrorLog.Add("Error running Disk Cleanup: $($_.Exception.Message)")
    Write-Warning "Error running Disk Cleanup: $($_.Exception.Message)"
}

# Generate final report
New-Object CleanupEntry -ArgumentList Windows Disk Cleanup, System Utility, "$cleanupFreed MB", "Success"
if ($ErrorLog.Count -gt 0) {
    Write-Host "`n=== ERRORS ===" -ForegroundColor Red
    $ErrorLog | ForEach-Object { Write-Host $_ -ForegroundColor Red }
}

# Output for Datto RMM monitoring
$OutputData = @{
    TotalSpaceFreedMB = [math]::Round($TotalSpaceFreed, 2)
    TotalSpaceFreedGB = [math]::Round($TotalSpaceFreed / 1024, 2)
    LocationsCleaned  = $CleanupReport.Count
    ErrorCount        = $ErrorLog.Count
    Status            = if ($ErrorLog.Count -eq 0) { "Success" }else { "Warning" }
}

Write-Host "`nDATTO_OUTPUT: $($OutputData | ConvertTo-Json -Compress)" -ForegroundColor Magenta

# Set appropriate exit code for Datto RMM
if ($ErrorLog.Count -eq 0) {
    Write-Host "`nCleanup completed successfully!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`nCleanup completed with warnings. Check error log." -ForegroundColor Yellow
    exit 1
}

# Common locations where GUID folders appear
$guidLocations = @(
    "$UserProfile", # Root of user profile
    "$UserProfile\AppData\Local",
    "$UserProfile\AppData\Roaming",
    "$UserProfile\AppData\LocalLow"
)

Write-Host "  Scanning for GUID-named folders..." -ForegroundColor Yellow
$totalGuidFoldersRemoved = 0
$totalGuidSpaceFreed = 0

foreach ($location in $guidLocations) {
    try {
        if (-not (Test-Path $location)) { continue }

        $guidFolders = Get-ChildItem -Path $location -Directory -ErrorAction SilentlyContinue |
        Where-Object { $null -ne $_.Name -and $_.Name -match $guidPattern }

        if ($null -eq $guidFolders -or $guidFolders.Count -eq 0) { continue }

        foreach ($guidFolder in $guidFolders) {
            try {
                if ($null -eq $guidFolder -or $null -eq $guidFolder.FullName) { continue }

                $folderSize = Get-FolderSize -Path $guidFolder.FullName

                # Skip if folder is in use or contains critical files
                $criticalFiles = Get-ChildItem -Path $guidFolder.FullName -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @('.exe', '.dll', '.sys', '.msi') }

                if ($null -ne $criticalFiles -and $criticalFiles.Count -gt 0) {
                    Write-Host "    Skipping GUID folder with critical files: $($guidFolder.Name)" -ForegroundColor Gray
                    continue
                }

                Remove-Item -Path $guidFolder.FullName -Recurse -Force -ErrorAction Stop
                $totalGuidFoldersRemoved++
                $totalGuidSpaceFreed = New-Object System.Collections.ArrayList
                $null = $totalGuidSpaceFreed.Add($folderSize)

                Write-Verbose "Removed GUID folder: $($guidFolder.FullName) ($folderSize MB)"
            }
            catch {
                $null = $script:ErrorLog.Add("Error removing GUID folder $($guidFolder.FullName): $($_.Exception.Message)")
                continue
            }
        }
    }
    catch {
        $null = $script:ErrorLog.Add("Error scanning for GUID folders in $location : $($_.Exception.Message)")
        continue
    }
}

if ($totalGuidFoldersRemoved -gt 0) {
    $null = $script:TotalSpaceFreed.Add($totalGuidSpaceFreed)
    $null = $script:CleanupReport.Add([PSCustomObject]@{
        Location   = "GUID Folders - $Username"
        Path       = $UserProfile
        SpaceFreed = "$totalGuidSpaceFreed MB"
        Status     = "Success - $totalGuidFoldersRemoved folders removed"
    })
    Write-Host "    ✓ GUID Folders: $totalGuidFoldersRemoved folders removed, $totalGuidSpaceFreed MB freed" -ForegroundColor Green
}
else {
    Write-Host "    No GUID folders found to remove" -ForegroundColor Gray
}

function Remove-OldUserFiles {
    param([string]$UserProfile, [string]$Username)

    New-Object CleanupEntry -ArgumentList GUID Folders - $Username, $UserProfile, "$totalGuidSpaceFreed MB", "Success - $totalGuidFoldersRemoved folders removed"

    $cutoffDate = (Get-Date).AddDays(-$FileAgeThresholdDays)
    $foldersToClean = @{
        "Downloads" = "$UserProfile\Downloads"
        "Documents" = "$UserProfile\Documents"
    }

    foreach ($folder in $foldersToClean.GetEnumerator()) {
        try {
            $folderPath = $folder.Value
            if ([string]::IsNullOrEmpty($folderPath) -or -not (Test-Path $folderPath)) {
                continue
            }

            Write-Host "  Scanning $($folder.Key) for files older than $FileAgeThresholdDays days..." -ForegroundColor Yellow

            $allFiles = Get-ChildItem -Path $folderPath -File -Recurse -ErrorAction SilentlyContinue
            if ($null -eq $allFiles) {
                Write-Host "    No files found in $($folder.Key)" -ForegroundColor Gray
                continue
            }

            $oldFiles = @()
            foreach ($file in $allFiles) {
                try {
                    if ($null -ne $file -and
                        $null -ne $file.LastWriteTime -and
                        $null -ne $file.Extension -and
                        $file.LastWriteTime -lt $cutoffDate -and
                        $file.Extension -notin $ProtectedExtensions) {
                        $null = $oldFiles.Add($file)
                    }
                }
                catch {
                    # Skip files that can't be accessed
                    continue
                }
            }

            if ($oldFiles.Count -eq 0) {
                Write-Host "    No old files found in $($folder.Key)" -ForegroundColor Gray
                continue
            }

            $sizeBefore = 0
            foreach ($file in $oldFiles) {
                if ($null -ne $file -and $null -ne $file.Length) {
                    $null = $sizeBefore.Add($file.Length)
                }
            }
            $sizeBeforeMB = [math]::Round($sizeBefore / 1MB, 2)

            $deletedCount = 0
            foreach ($file in $oldFiles) {
                try {
                    if ($null -ne $file -and $null -ne $file.FullName -and (Test-Path $file.FullName)) {
                        Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                        $deletedCount++
                    }
                }
                catch {
                    $null = $script:ErrorLog.Add("Error deleting old file $($file.FullName): $($_.Exception.Message)")
                    continue
                }
            }

            if ($deletedCount -gt 0) {
                $null = $script:TotalSpaceFreed.Add($sizeBeforeMB)
                $null = $script:CleanupReport.Add([PSCustomObject]@{
                    Location   = "$($folder.Key) Old Files - $Username"
                    Path       = $folderPath
                    SpaceFreed = "$sizeBeforeMB MB"
                    Status     = "Success - $deletedCount files deleted"
                })
                Write-Host "    ✓ $($folder.Key): $deletedCount old files deleted, $sizeBeforeMB MB freed" -ForegroundColor Green
            }
        }
        catch {
            $null = $script:ErrorLog.Add("Error processing old files in $($folder.Key) for $Username`: $($_.Exception.Message)")
            Write-Warning "  Error processing old files in $($folder.Key): $($_.Exception.Message)"
        }
    }
}
New-Object CleanupEntry -ArgumentList $($folder.Key) Old Files - $Username, $folderPath, "$sizeBeforeMB MB", "Success - $deletedCount files deleted"
$UserProfiles = Get-WmiObject -Class Win32_UserProfile |
Where-Object {
    $null -ne $_ -and
    $_.Special -eq $false -and
    $null -ne $_.LocalPath -and
    $_.LocalPath -notlike "*\Windows\*" -and
    $_.LocalPath -ne ""
}

if ($null -eq $UserProfiles) {
    Write-Warning "No user profiles found to process"
    $UserProfiles = @()
}

Write-Host "Found $($UserProfiles.Count) user profiles to process" -ForegroundColor Yellow

catch {
    Write-Error "Failed to enumerate user profiles: $($_.Exception.Message)"
    exit 1
}

# Clean each user profile
foreach ($Profile in $UserProfiles) {
    try {
        if ($null -eq $Profile -or $null -eq $Profile.LocalPath) {
            continue
        }

        $UserPath = $Profile.LocalPath
        if ([string]::IsNullOrEmpty($UserPath) -or -not (Test-Path $UserPath)) {
            Write-Warning "Skipping invalid user profile path: $UserPath"
            continue
        }

        $Username = Split-Path $UserPath -Leaf
        if ([string]::IsNullOrEmpty($Username)) {
            Write-Warning "Skipping profile with empty username: $UserPath"
            continue
        }

        Write-Host "`nProcessing user: $Username" -ForegroundColor Cyan

        # User-specific temp and cache locations
        $userCleanupPaths = @{
            "User Temp - $Username"             = "$UserPath\AppData\Local\Temp"
            "User Temp2 - $Username"            = "$UserPath\AppData\Local\Tmp"
            "Recent Items - $Username"          = "$UserPath\AppData\Roaming\Microsoft\Windows\Recent"
            "Thumbnail Cache - $Username"       = "$UserPath\AppData\Local\Microsoft\Windows\Explorer"
            "Windows Error Reports - $Username" = "$UserPath\AppData\Local\Microsoft\Windows\WER"
            "CrashDumps - $Username"            = "$UserPath\AppData\Local\CrashDumps"
            "Adobe Cache - $Username"           = "$UserPath\AppData\Local\Adobe\*\Cache"
            "Teams Cache - $Username"           = "$UserPath\AppData\Roaming\Microsoft\Teams\tmp"
            "Skype Cache - $Username"           = "$UserPath\AppData\Roaming\Skype\*\chatsync"
            "Discord Cache - $Username"         = "$UserPath\AppData\Roaming\discord\Cache"
            "Spotify Cache - $Username"         = "$UserPath\AppData\Local\Spotify\Storage"
            "Steam Logs - $Username"            = "$UserPath\AppData\Local\Steam\logs"
        }

        # Clean user-specific locations
        foreach ($location in $userCleanupPaths.GetEnumerator()) {
            try {
                if ([string]::IsNullOrEmpty($location.Value)) { continue }

                $paths = Get-ChildItem -Path $location.Value -ErrorAction SilentlyContinue
                if ($null -ne $paths) {
                    foreach ($path in $paths) {
                        if ($null -ne $path -and $null -ne $path.FullName) {
                            Remove-DirectoryContents -Path $path.FullName -Description $location.Key
                        }
                    }
                }
            }
            catch {
                $null = $ErrorLog.Add("Error processing location $($location.Key): $($_.Exception.Message)")
                continue
            }
        }

        # Clean browser caches
        Clear-BrowserCaches -UserProfile $UserPath -Username $Username

        # Clean old files from Downloads and Documents
        Remove-OldUserFiles -UserProfile $UserPath -Username $Username

    }
    catch {
        $null = $ErrorLog.Add("Error processing user $Username`: $($_.Exception.Message)")
        Write-Warning "Error processing user $Username`: $($_.Exception.Message)"
    }
}

Write-Host "`nCleaning system-wide locations..." -ForegroundColor Cyan

# System-wide cleanup locations
$systemCleanupPaths = @{
    "Windows Temp"          = "$env:WINDIR\Temp"
    "System Temp"           = "$env:TEMP"
    "Prefetch"              = "$env:WINDIR\Prefetch"
    "Software Distribution" = "$env:WINDIR\SoftwareDistribution\Download"
    "CBS Logs"              = "$env:WINDIR\Logs\CBS"
    "DISM Logs"             = "$env:WINDIR\Logs\DISM"
    "Windows Update Logs"   = "$env:WINDIR\WindowsUpdate.log*"
    "Memory Dumps"          = "$env:WINDIR\Minidump"
    "Error Reports"         = "$env:ALLUSERSPROFILE\Microsoft\Windows\WER"
    "Delivery Optimization" = "$env:WINDIR\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Logs"
}

foreach ($location in $systemCleanupPaths.GetEnumerator()) {
    Remove-DirectoryContents -Path $location.Value -Description $location.Key
}

# Clean Recycle Bin
Write-Host "`nEmptying Recycle Bin..." -ForegroundColor Yellow
try {
    $sizeBefore = 0
    $recycleBins = Get-ChildItem -Path "C:\`$Recycle.Bin" -Directory -ErrorAction SilentlyContinue

    if ($null -ne $recycleBins) {
        foreach ($bin in $recycleBins) {
            if ($null -ne $bin -and $null -ne $bin.FullName) {
                $null = $sizeBefore.Add((Get-FolderSize -Path $bin.FullName))
            }
        }
    }

    # Empty recycle bin using Shell.Application with better error handling
    $shell = $null
    $recycleBin = $null
    try {
        $shell = New-Object -ComObject Shell.Application
        if ($null -ne $shell) {
            $recycleBin = $shell.Namespace(0xA)
            if ($null -ne $recycleBin) {
                $items = $recycleBin.Items()
                if ($null -ne $items) {
                    foreach ($item in $items) {
                        try {
                            if ($null -ne $item) {
                                $item.InvokeVerb("delete")
                            }
                        }
                        catch {
                            # Continue with other items if one fails
                            continue
                        }
                    }
                }
            }
        }
    }
    finally {
        # Clean up COM objects
        if ($null -ne $recycleBin) {
            [void][System.Runtime.Interopservices.Marshal]::ReleaseComObject($recycleBin)
        }
        if ($null -ne $shell) {
            [void][System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell)
        }
    }

    if ($sizeBefore -gt 0) {
        $null = $CleanupReport.Add([PSCustomObject]@{
            Location   = "Recycle Bin"
            Path       = "C:\`$Recycle.Bin"
            SpaceFreed = "$sizeBefore MB"
            Status     = "Success"
        })
        $null = $TotalSpaceFreed.Add($sizeBefore)
        Write-Host "✓ Recycle Bin: $sizeBefore MB freed" -ForegroundColor Green
    }

    catch {
        $null = $ErrorLog.Add("Error emptying Recycle Bin: $($_.Exception.Message)")
        Write-Warning "Error emptying Recycle Bin: $($_.Exception.Message)"
    }


    New-Object CleanupEntry -ArgumentList Recycle Bin, C:\`$Recycle.Bin, "$sizeBefore MB", "Success"
    $cleanupAfter = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq "C:" } | Select-Object -ExpandProperty FreeSpace
    $cleanupFreed = [math]::Round(($cleanupAfter - $cleanupBefore) / 1MB, 2)

    if ($cleanupFreed -gt 0) {
        $null = $TotalSpaceFreed.Add($cleanupFreed)
        $null = $CleanupReport.Add([PSCustomObject]@{
            Location   = "Windows Disk Cleanup"
            Path       = "System Utility"
            SpaceFreed = "$cleanupFreed MB"
            Status     = "Success"
        })
        Write-Host "✓ Windows Disk Cleanup: $cleanupFreed MB freed" -ForegroundColor Green
    }
}
catch {
    $null = $ErrorLog.Add("Error running Disk Cleanup: $($_.Exception.Message)")
    Write-Warning "Error running Disk Cleanup: $($_.Exception.Message)"
}

# Generate final report
New-Object CleanupEntry -ArgumentList Windows Disk Cleanup, System Utility, "$cleanupFreed MB", "Success"
if ($ErrorLog.Count -gt 0) {
    Write-Host "`n=== ERRORS ===" -ForegroundColor Red
    $ErrorLog | ForEach-Object { Write-Host $_ -ForegroundColor Red }
}

# Output for Datto RMM monitoring
$OutputData = @{
    TotalSpaceFreedMB = [math]::Round($TotalSpaceFreed, 2)
    TotalSpaceFreedGB = [math]::Round($TotalSpaceFreed / 1024, 2)
    LocationsCleaned  = $CleanupReport.Count
    ErrorCount        = $ErrorLog.Count
    Status            = if ($ErrorLog.Count -eq 0) { "Success" }else { "Warning" }
}

Write-Host "`nDATTO_OUTPUT: $($OutputData | ConvertTo-Json -Compress)" -ForegroundColor Magenta

# Set appropriate exit code for Datto RMM
if ($ErrorLog.Count -eq 0) {
    Write-Host "`nCleanup completed successfully!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`nCleanup completed with warnings. Check error log." -ForegroundColor Yellow
    exit 1
}

#region SYSTEM STORAGE OPTIMIZATION
Function Disable-Hibernation {
    try {
        powercfg -h off | Out-Null
        Write-Host "Hibernation disabled successfully."
    }
    catch {
        Write-Warning "Failed to disable hibernation: $_"
    }
}


Function Optimize-PageFile {
    try {
        $ramBytes = (Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory
        $ramMB = [math]::Floor($ramBytes / 1MB)
        $ramLimit = $ramMB

        $pagefile = Get-WmiObject -Query "SELECT * FROM Win32_PageFileSetting"
        foreach ($pf in $pagefile) {
            $maxSize = $pf.MaximumSize
            if ($maxSize -ge ($ramMB * 1.25)) {
                Write-Host "Page file too large ($maxSize MB). Attempting to reduce to $ramLimit MB..."
                $pf.InitialSize = $ramLimit
                $pf.MaximumSize = $ramLimit
                $result = $pf.Put()
                if ($result.ReturnValue -ne 0) {
                    throw "Resizing page file failed with code $($result.ReturnValue)"
                }
                else {
                    Write-Host "Page file resized successfully to $ramLimit MB"
                }
            }
            else {
                Write-Host "Page file size is acceptable ($maxSize MB)"
            }
        }
    }
    catch {
        Write-Warning "Page file optimization failed: $_"
        Write-Warning "Disabling page file as fallback..."
        try {
            $os = Get-WmiObject Win32_OperatingSystem
            $os.AutomaticManagedPagefile = $false
            $os.Put() | Out-Null

            $pagefiles = Get-WmiObject Win32_PageFileSetting
            foreach ($pf in $pagefiles) {
                $pf.Delete() | Out-Null
            }
            Write-Host "Page file disabled successfully."
        }
        catch {
            Write-Error "Failed to disable page file: $_"
        }
    }
}


Function Clean-RootJunkDirectories {
    $WindowsDefaultDirs = @(
        'PerfLogs', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Users', 'Windows'
    )
    $RootPath = 'C:\'
    $freed = 0

    $dirs = Get-ChildItem -Path $RootPath -Directory -Force | Where-Object {
        $_.Name -notin $WindowsDefaultDirs
    }

    foreach ($dir in $dirs) {
        try {
            $size = (Get-ChildItem -Path $dir.FullName -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
            $freed = New-Object System.Collections.ArrayList
            $null = $freed.Add($size)
            Write-Host "Removed junk directory: $($dir.FullName)"
        }
        catch {
            Write-Warning "Failed to remove $($dir.FullName): $_"
        }
    }

    return $freed
}
#endregion
[void]([GC]::ReleaseComObject($shell));
[void]([GC]::Collect());

# Execute system-level storage optimizations
Disable-Hibernation
Optimize-PageFile
$null = $TotalSpaceFreed.Add((Clean-RootJunkDirectories))

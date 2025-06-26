#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    $LogProfile = $null,
    [switch]$Dump
)

Set-StrictMode -Version Latest

$folder = "WslLogs-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')"
New-Item -ItemType Directory -Path $folder -Force | Out-Null

# Download log profile if needed
if (-not $LogProfile -or -not (Test-Path $LogProfile)) {
    $urls = @{
        $null = "https://raw.githubusercontent.com/microsoft/WSL/master/diagnostics/wsl.wprp"
        "storage" = "https://raw.githubusercontent.com/microsoft/WSL/master/diagnostics/wsl_storage.wprp"
    }
    
    if (-not $urls.ContainsKey($LogProfile)) {
        Write-Error "Unknown log profile: $LogProfile"
        exit 1
    }
    
    $LogProfile = "$folder/wsl.wprp"
    Invoke-WebRequest -UseBasicParsing $urls[$LogProfile -eq "$folder/wsl.wprp" ? $null : $LogProfile] -OutFile $LogProfile
}

# Export registry keys
$regKeys = @{
    "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Lxss" = "HKCU.txt"
    "HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Lxss" = "HKLM.txt"
    "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\P9NP" = "P9NP.txt"
    "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\WinSock2" = "Winsock2.txt"
    "HKEY_CLASSES_ROOT\CLSID\{e66b0f30-e7b4-4f8c-acfd-d100c46c6278}" = "wslsupport-proxy.txt"
    "HKEY_CLASSES_ROOT\CLSID\{a9b7a1b9-0671-405c-95f1-e0612cb4ce7e}" = "wslsupport-impl.txt"
}

$regKeys.GetEnumerator() | ForEach-Object {
    reg.exe export $_.Key "$folder/$($_.Value)" 2>$null | Out-Null
}

# Copy WSL config if exists
$wslconfig = "$env:USERPROFILE/.wslconfig"
if (Test-Path $wslconfig) {
    Copy-Item $wslconfig $folder
}

# Collect system information
Get-AppxPackage MicrosoftCorporationII.WindowsSubsystemforLinux -ErrorAction Ignore > "$folder/appxpackage.txt"
Get-Acl "C:\ProgramData\Microsoft\Windows\WindowsApps" -ErrorAction Ignore | Format-List > "$folder/acl.txt"
Get-WindowsOptionalFeature -Online > "$folder/optional-components.txt"
bcdedit.exe > "$folder/bcdedit.txt"

# Start WPR logging
$wprLog = "$folder/wpr.txt"
wpr.exe -start $LogProfile -filemode 2>&1 >> $wprLog

if ($LASTEXITCODE -ne 0) {
    Write-Host "Log collection failed, resetting..." -ForegroundColor Yellow
    wpr.exe -cancel 2>&1 >> $wprLog
    wpr.exe -start $LogProfile -filemode 2>&1 >> $wprLog
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Couldn't start log collection (exit code: $LASTEXITCODE)" -ForegroundColor Red
    }
}

try {
    Write-Host "Log collection running. " -NoNewline
    Write-Host "Reproduce the problem " -ForegroundColor Red -NoNewline
    Write-Host "then press any key to save logs."
    
    # Wait for valid key press (excluding modifier keys)
    $ignoreKeys = 16,17,18,20,91,92,93,144,145,166..183
    do {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    } while ($key.VirtualKeyCode -in $ignoreKeys)
    
    Write-Host "`nSaving logs..."
}
finally {
    wpr.exe -stop "$folder/logs.etl" 2>&1 >> $wprLog
}

# Create process dumps if requested
if ($Dump) {
    $dumpFolder = "$folder/dumps"
    New-Item -ItemType Directory -Path $dumpFolder -Force | Out-Null
    
    $assembly = [PSObject].Assembly.GetType('System.Management.Automation.WindowsErrorReporting')
    $dumpMethod = $assembly.GetNestedType('NativeMethods', 'NonPublic').GetMethod('MiniDumpWriteDump', 'NonPublic,Static')
    
    Get-Process | Where-Object { $_.ProcessName -in @("wsl", "wslservice", "wslhost", "msrdc") } | ForEach-Object {
        $dumpFile = "$dumpFolder/$($_.ProcessName).$($_.Id).dmp"
        Write-Host "Writing $dumpFile"
        
        try {
            $fileStream = [IO.FileStream]::new($dumpFile, [IO.FileMode]::Create)
            $result = $dumpMethod.Invoke($null, @($_.Handle, $_.Id, $fileStream.SafeFileHandle, 2, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero))
            $fileStream.Close()
            
            if (-not $result) {
                Write-Host "Failed to write dump for: $dumpFile"
            }
        }
        catch {
            Write-Warning "Failed to create dump for $($_.ProcessName): $($_.Exception.Message)"
        }
    }
}

# Create archive and cleanup
$logArchive = "$(Resolve-Path $folder).zip"
Compress-Archive -Path $folder -DestinationPath $logArchive -Force
Remove-Item $folder -Recurse -Force

Write-Host "Logs saved in: $logArchive. Please attach to GitHub issue." -ForegroundColor Green

nction NukeOffice {
    param(
        [switch]$Reinstall64,
        [switch]$Reinstall32,
        [switch]$noreinstall
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $zipPath = Join-Path -Path $env:HOMEDRIVE -ChildPath "SaRACMD.zip"
    $downloadUrl = "https://aka.ms/SaRA_EnterpriseVersionFiles"
    $O365setup64 = "C:\Users\OfficeSetup64.exe"
    $O365setup32 = "C:\Users\OfficeSetup32.exe"
    $O365Url64 = "https://c2rsetup.officeapps.live.com/c2r/download.aspx?productReleaseID=O365ProPlusRetail&platform=X64&language=en-us"
    $O365Url32 = "https://c2rsetup.officeapps.live.com/c2r/download.aspx?productReleaseID=O365ProPlusRetail&platform=X86&language=en-us"
    $retry = 3
    $timeout = 30
    $killIfinvokefails = @("lync", "winword", "excel", "msaccess", "mstore", "infopath", "setlang", "msouc", "ois", "onenote", "outlook", "powerpnt", "mspub", "groove", "visio", "winproj", "graph", "teams")

    #download extract
    [console]::writeline("Downloading SaRACMD tool...")
    $attempt = 0
    while ($attempt -lt $retry) {
        try {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $env:windir) #this is if using shit ps version like in datto agent browser.
            break
        } catch {
            Write-Warning "Attempt failed. Error: $_"
            $attempt++
            if ($attempt -eq $retry) {
                throw "Failed to download SaRACMD after $retry attempts."
            }
            Start-Sleep -Seconds $timeout
        }
    }

    #invoek
    try {
        & "$env:windir\SaRACMD.exe" -S OfficeScrubScenario -AcceptEula -OfficeVersion All #most likely issue is office processes are running.
    } catch {
        Write-Warning "Execution failed. Attempting to stop running Office processes..."
        $killIfinvokefails | ForEach-Object {
            Get-Process $_ -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        throw "Failed to execute SaRACMD after stopping processes. Error: $_"
    }


    if ($Reinstall64) {
        [console]::writeline("Reinstalling 64bit...") #device should probably be rebooted before this. very basic office configuration
        Invoke-WebRequest -Uri $O365Url64 -OutFile $O365setup64
        Start-Process -FilePath $O365setup64 -Wait
    } elseif ($Reinstall32) {
        [console]::writeline( "Reinstalling 32-bit...") #device should probably be rebooted before this. very basic office configuration
        Invoke-WebRequest -Uri $O365Url32 -OutFile $O365setup32
        Start-Process -FilePath $O365setup32 -Wait
    } elseif ($noreinstall){
        [console]::writeline("Done")
    }
}
NukeOffice -noreinstall

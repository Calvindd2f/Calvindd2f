# SystemInfoModule.psm1

#region INPUT VARIABLES

#endregion

#region OUTPUT VARIABLES
$variableProps = @{ Members = $null; Data = $null; UserInfo  = $null; OtherInfo = $null; largestFiles = $null; unresponsiveProcesses = $null; TempCount=$null; TempSize=$null; sessionType = $null; lastBootTime = $null; hotFix = $null; powerProfile = $null; CPUload = $null; ProcessMemory = $null; maxMemory = $null; consumedMemory = $null; }
$outputProps = @{ out = [psobject]::new($variableProps); success = $false }
$activityOutput = [psobject]::new($outputProps)
#endregion

#region FUNCTIONS
function GetDebugDetails {
    try {
        $details = Get-WmiObject Win32_OperatingSystem | Select PSComputerName, Caption, OSArchitecture, Version, BuildNumber
        Write-Host "Debug Details: "
        Write-Host "OS: $($details.Caption)"
        Write-Host "OS Architecture: $($details.OSArchitecture)"
        Write-Host "Computer Name: $($details.PSComputerName)"
        Write-Host "Version: $($details.Version)"
        Write-Host "Build Number: $($details.BuildNumber)"
    } catch {
        Write-Host $_.Exception.Message
    }
}

function GetUserDetails {
    try {
        $Active = Get-WmiObject Win32_LoggedOnUser | Select Antecedent -Unique | Where-Object { $_.Antecedent.ToString().Split('"')[1] -ne $($env:COMPUTERNAME) -and $_.Antecedent.ToString().Split('"')[1] -ne "Window Manager" -and $_.Antecedent.ToString().Split('"')[3] -notmatch $env:COMPUTERNAME } | % { "{0}\{1}" -f $_.Antecedent.ToString().Split('"')[1], $_.Antecedent.ToString().Split('"')[3] } | Where { $_ -notlike "NT AUTHORITY*" -and $_ -notlike "*\UMFD-*" -and $_ -notlike "*\DWM-*" -and $_ -notlike "*\LOCAL SERVICE*" -and $_ -notlike "*\NETWORK SERVICE*" -and $_ -notlike "*\*-*-*-*-*" }
        $Inactive = Get-WmiObject Win32_LoggedOnUser | Select Antecedent -Unique | % { "{0}\{1}" -f $_.Antecedent.ToString().Split('"')[1], $_.Antecedent.ToString().Split('"')[3] } | Where { $_ -notlike "NT AUTHORITY*" -and $_ -notlike "*\UMFD-*" -and $_ -notlike "*\DWM-*" -and $_ -notlike "*\LOCAL SERVICE*" -and $_ -notlike "*\NETWORK SERVICE*" -and $_ -notlike "*\*-*-*-*-*" -and $_ -ne $Active }

        [string]$LoggedIn = $null
        foreach ($user in $Active) {
            $LoggedIn += "$user - Active`n"
        }
        foreach ($user in $Inactive) {
            $LoggedIn += "$user - Disc`n"
        }
        $activityOutput.out.UserInfo = $LoggedIn
    } catch {
        Write-Host $_.Exception.Message
    }
}

function GetLargestFiles {
    try {
        $files = $null
        foreach ($disk in (Get-WmiObject Win32_LogicalDisk)) {
            if ($disk.DriveType -ne 5 -and $disk.DriveType -ne 2 -and $disk.DriveType -ne 4) {
                $files = Get-ChildItem -Path "$($disk.Name)" -Recurse -ErrorAction SilentlyContinue | Select FullName, Length | sort -Descending -Property length | select -First 5 | select fullname, @{Name = 'Gigabytes'; Expression = { [math]::round($_.length / 1GB, 2) } }
                write-host "Done Scanning $($disk.Name)"
                write-host $files
            }
        }
        foreach ($file in $files) {
            $activityOutput.out.largestFiles += $file
            $filepath += "$($file.Gigabytes)GB - $($file.fullname)`r`n"
        }
        return $filepath
    } catch {
        Write-Host $_.Exception.Message
    }
}

function GetMachineDetails {
    try {
        #-----Check for hung processes-----
        Write-host "checking hung processes"
        $allUnresponsiveProcesses = get-process * | where { $_.responding -eq $false }
        $activityOutput.out.unresponsiveProcesses = "None"

        $unresponsive = @()
        foreach ($unProc in $allUnresponsiveProcesses) {
            $suspendedProcess = $false
            foreach ($thread in $unProc.threads) {
                if ($thread.waitReason -eq "Suspended") {
                    $suspendedProcess = $true
                    break
                }
            }
            if ($suspendedProcess -eq $false) {
                $unresponsive += "$($unProc.name)<br />"
            }
        }

        #-----Check Network-----
        Write-host "checking network"
        $adpaterName = ""
        if ($connection -eq "Wireless") {
            $adapaterName = (netsh wlan show interfaces) -Match '^\s+Name' -Replace '^\s+Name\s+:\s+', ''
        } else {
            if ((get-service dot3svc).status -ne "Running") {
                Start-Service dot3svc -ea SilentlyContinue -wa SilentlyContinue
                start-sleep -seconds 5
            }
            $adapaterName = (netsh lan show interfaces) -Match '^\s+Name' -Replace '^\s+Name\s+:\s+', ''
        }
        Write-Host $adapaterName
        if (![string]::IsNullOrEmpty($adapaterName)) {
            $gateway = (Get-NetIPConfiguration).ipv4defaultGateway.nexthop
        }

        $reachedGateway = $false
        try {
            if (Test-Connection $gateway -count 3 -ea Stop) {
                $reachedGateway = $true
            }
        } catch {
            Write-Host $($_.Exception.Message)
        }

        $netConnected = $false
        try {
            if (Test-Connection 8.8.8.8 -ea Stop) {
                $netConnected = $true
            }
        } catch {
            Write-Host $($_.Exception.Message)
        }

        #-----Check for Temp files----
        Write-host "checking temp files"
        $Tempfolders = @()
        $TempFolders += "C:\Windows\Temp\*"
        $TempFolders += "C:\Windows\Prefetch\*"
        $Tempfiles = get-childitem -path $tempfolders
        $UserPaths = Get-ChildItem -Path "C:\Users\*"
        foreach ($user in $UserPaths) {
            if (Test-Path (Join-Path $user.FullName '\AppData\Local\Temp')) {
                $Tempfiles += Get-ChildItem -Path (Join-Path $user.FullName '\AppData\Local\Temp') -Recurse
            }
        }
        $Size = $Tempfiles | measure Length -s
        $Tempfiles.Count
        $Filesize = [math]::Round($Size.Sum / 1MB, 2)
        $activityOutput.out.TempCount = $Tempfiles.Count
        $activityOutput.out.TempSize = $Filesize
        [Array]$objNetworkInfo = [pscustomobject]@()
        Import-Module NetTCPIP -Force | Out-Null
        $ip_var = $(Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -ne "Disconnected" }).IPv4Address.IPAddress
        [Array]$NetworkIPInfo = [pscustomobject]@()
        $NetworkIPInfo += [pscustomobject]@{ IP = "IPv4 Address: $ip_var"; }
        $objNetworkInfo += [pscustomobject]@{
            IPAddress    = "IP Address: $ip_var";
            Gateway      = "Gateway: $gateway";
            ReachedGateway = "Reached Gateway: $($reachedGateway.ToString())";
            NetConnected = "Net Connected: $($netConnected.ToString())";
        }

        $MachineProperties = new-object psobject
        #---Get Computer Type (Desktop/Remote)------
        Write-host "getting computer type"
        $sessionType = $null
        $sessionType = $env:SessionName
        [Array]$NetworkTypeInfo = [pscustomobject]@()
        if ($sessionType -eq $null -or $sessionType -eq "" -or $sessionType.ToLower() -eq "console") {
            $activityOutput.out.sessionType = "local"
            $sessionType = "local"
        } else {
            $activityOutput.out.sessionType = "remote"
            $sessionType = "remote"
        }

        #----Check if on Wireless or Ethernet-----
        Write-host "getting network type"
        if ($sessionType -eq "local") {
            $connType = $null
            try {
                $service = Get-Service -Name 'WlanSvc' -ErrorAction Stop
                if ($service) {
                    if ((Get-service WlanSvc).Status -eq "Running") {
                        $SSID = $((netsh wlan show interfaces) -Match '^\s+SSID' -Replace '^\s+SSID\s+:\s+', '')
                        if ($SSID -eq $null -or $SSID.Length -eq 0) {
                            $connType = "Ethernet"
                            $NetworkTypeInfo += [pscustomobject]@{ ConnType = "Connection Type: Ethernet"; SSID = "SSID: N/A"; SignalStrength = "Signal Strength: N/A"; }
                        } else {
                            $connType = "Wireless"
                            $signalStrength = (netsh wlan show interfaces) -Match '^\s+Signal' -Replace '^\s+Signal\s+:\s+', ''
                            $NetworkTypeInfo += [pscustomobject]@{ ConnType = "Connection Type: Wireless"; SSID = "SSID: $SSID"; SignalStrength = "Signal Strength: $signalStrength"; }
                        }
                    } else {
                        $connType = "Ethernet"
                        $NetworkTypeInfo += [pscustomobject]@{ ConnType = "Connection Type: Ethernet"; SSID = "SSID: N/A"; SignalStrength = "Signal Strength: N/A"; }
                    }
                } else {
                    Write-Host "WlanSvc Not found from else"
                }
            } catch [Microsoft.PowerShell.Commands.ServiceCommandException] {
                Write-Host "WlanSvc Not found from catch"
            }
        } else {
            $connType = "Ethernet"
            $NetworkTypeInfo += [pscustomobject]@{ ConnType = "Connection Type: Ethernet"; SSID = "SSID: N/A"; SignalStrength = "Signal Strength: N/A"; }
        }

        #----Last Time machine turned on-------
        Write-host "getting uptime"
        $lastBootTime = (Get-CimInstance Win32_OperatingSystem | select LastBootUpTime).LastBootupTime
        $LastBootTimeAus = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId(($lastBootTime), 'AUS Eastern Standard Time').toString('dd/MM/yyyy h:mm tt')
        $activityOutput.out.lastBootTime = $lastBootTimeAus
        [Array]$GeneralSystemInfo = [pscustomobject]@()
        $GeneralSystemInfo += [pscustomobject]@{
            LastBootTime = "Last Boot Time: $lastBootTimeAus";
            Unresponsive = $unresponsive;
            TempCount  = $Tempfiles.Count;
            TempSize   = $Filesize
        }

        #----Get Build Information-----
        Write-Host "getting General Computer Information"
        $wmiOSInfo = Get-WmiObject Win32_OperatingSystem
        $BuildNo = $($wmiOSInfo.BuildNumber)
        [string]$Win10Ver = switch ($BuildNo) {
            "10240" { "1507" }
            "10586" { "1511" }
            "14393" { "1607" }
            "15063" { "1703" }
            "16299" { "1709" }
            "17134" { "1803" }
            "17763" { "1809" }
            "18362" { "1903" }
            "18363" { "1909" }
            "19041" { "2004" }
            "19042" { "20H2" }
            "19043" { "21H1" }
            "19044" { "21H2" }
            "22621" { "22H2" }
        }
        [string]$Release = switch ($BuildNo) {
            "10240" { "(Released Jul 2015)" }
            "10586" { "(Released Nov 2015)" }
            "14393" { "(Released Aug 2016)" }
            "15063" { "(Released Apr 2017)" }
            "16299" { "(Released Oct 2017)" }
            "17134" { "(Released Apr 2018)" }
            "17763" { "(Released Nov 2018)" }
            "18362" { "(Released May 2019)" }
            "18363" { "(Released Nov 2019)" }
            "19041" { "(Released May 2020)" }
            "19042" { "(Released Oct 2020)" }
            "19043" { "(Released May 2021)" }
            "19044" { "TBA" }
            "22621" { "(Released Sep 2021)" }
        }
        Write-Host "Build: $BuildNo"
        if ([string]::IsNullOrEmpty($Win10Ver)) {
            $Win10Ver = "Unable to find OS Version"
            Write-Host "Version: $Win10Ver"
        } else {
            Write-Host "Version: $Win10Ver"
        }

        $is64bit = [System.Environment]::Is64BitOperatingSystem
        if ($is64bit) {
            [string]$OSBitType = "64-Bit"
        } else {
            [string]$OSBitType = "32-Bit"
        }

        $PCInfo = Get-WmiObject Win32_ComputerSystem
        $PCInfo2 = Get-WmiObject win32_ComputerSystemProduct
        $wmiCPUInfo = Get-WmiObject -Class Win32_Processor
        $wmiRAMInfo = Get-WmiObject win32_Physicalmemory
        $DriveInfo = Get-WmiObject -Class MSFT_PhysicalDisk -Namespace root\Microsoft\Windows\Storage
        $Enclosure = (Get-WmiObject Win32_SystemEnclosure).ChassisTypes
        [string]$DeviceType = switch ($Enclosure) {
            "1" { "Other" }
            "2" { "Unknown" }
            "3" { "Desktop" }
            "4" { "Low Profile Desktop" }
            "5" { "Pizza Box" }
            "6" { "Mini Tower" }
            "7" { "Tower" }
            "8" { "Portable" }
            "9" { "Laptop" }
            "10" { "Notebook" }
            "11" { "Hand Held" }
            "12" { "Docking Station" }
            "13" { "All in One" }
            "14" { "Sub Notebook" }
            "15" { "Space-Saving" }
            "16" { "Lunch Box" }
            "17" { "Main System Chassis" }
            "18" { "Expansion Chassis" }
            "19" { "SubChassis" }
            "20" { "Bus Expansion Chassis" }
            "21" { "Peripheral Chassis" }
            "22" { "Storage Chassis" }
            "23" { "Rack Mount Chassis" }
            "24" { "Sealed-Case PC" }
            "30" { "Tablet" }
            "31" { "Convertible" }
            "32" { "Detachable" }
        }

        [Array]$CPUInfo = [pscustomobject]@()
        $CPUInfo += [pscustomobject]@{Type = "CPU Type: $DeviceType"; Name = "CPU Name: $($wmiCPUInfo.Name)" }

        [Array]$OSInfo = [pscustomobject]@()
        $OSInfo += [pscustomobject]@{Edition = "Edition: $($wmiOSInfo.Caption) $OSBitType"; Version = "Version: $Win10Ver $Release"; Domain = "Domain: $($PCInfo.Domain)" }

        [Array]$RAMHardwareInfo = [pscustomobject]@()
        $i = 0
        foreach ($item in $wmiRAMInfo) {
            $i++
            $RAMHardwareInfo += [pscustomobject]@{ Count = $i; Manufacturer = "Manufacturer: $($item.Manufacturer)"; PartNumber = $("Part Number: $($item.PartNumber)").Trim(); Capacity = "Capacity: $($($item.Capacity)/1GB)GB"; }
        }
        if ($wmiRAMInfo -eq $null -and $(Get-WmiObject Win32_BaseBoard).Product -eq "Virtualbox") {
            $RAMHardwareInfo += [pscustomobject]@{ Count = 1; Manufacturer = "Manufacturer: Virtualbox"; PartNumber = "Part Number: None"; Capacity = "Capacity: Unknown"; }
        }

        $i = 0
        [Array]$DriveHardwareInfo = [pscustomobject]@()
        foreach ($item in $DriveInfo) {
            $i++
            $DriveHardwareInfo += [pscustomobject]@{ Count = $i; Manufacturer = "Manufacturer: $($item.FriendlyName)"; Type = "Type: $(switch($($item.MediaType)){ '3' {'HDD'}; '4' {'SSD'}; '0' {'Virtual'};})" }
        }

        [Array]$VendorInfo = [pscustomobject]@()
        $modelno = $($PCInfo2.Version)
        if ([string]::IsNullOrEmpty($modelno) -or $modelno -eq " ") {
            $modelno = "Not found."
        }
        $VendorInfo += [pscustomobject]@{Model = "Model: $($PCInfo2.Name)"; ModelNo = "Model No: $modelno"; Vendor = "Vendor: $($PCInfo2.Vendor)"; SerialNo = "Serial No: $($PCInfo2.IdentifyingNumber)" }

        #----Most Recent Patch------
        Write-host "getting patches"
        $hotfix = "$((Get-HotFix | Sort-Object InstalledOn -ErrorAction SilentlyContinue -Descending)[0].HotFixID) - Installed $(((Get-HotFix | Sort-Object InstalledOn -ErrorAction SilentlyContinue -Descending)[0].InstalledOn).toString('dd/MM/yyyy'))"
        $hotfix.Replace("`n", "<br />")
        # $activityOutput.out.hotFix = $hotfix

        Write-host "getting powerplan"
        if ($sessionType -eq "local") {
            $powerplan = (powercfg -GETACTIVESCHEME)
            $powerplan = $powerplan.Substring(0, $powerplan.Length - 1)
            $powerplan = $powerplan.Split('(')[-1]
            $battery = Get-WmiObject -Class Win32_Battery | Select-Object -First 1
            $noAC = $battery -ne $null -and $battery.BatteryStatus -eq 1
            if ($noAC) {
                $powerplan += " - On Battery"
            } else {
                $powerplan += " - On Mains"
            }
        }
        # $activityOutput.out.powerProfile = $powerplan
        [Array]$PowerInfo = [pscustomobject]@()
        $PowerInfo += [pscustomobject]@{ PowerPlan = $powerplan; }
        [Array]$CPULoad = [pscustomobject]@()

        #---Get CPU Load---
        Write-host "getting CPU"
        #$activityOutput.out.CPUload = (Get-WmiObject -Class win32_Processor -ErrorAction Stop | Select-Object LoadPercentage).LoadPercentage
        $CPULoad += [pscustomobject]@{ Load = "CPU Load: $((Get-WmiObject -Class win32_Processor -ErrorAction Stop | Select-Object LoadPercentage).LoadPercentage)%"; }

        #top 10 processes
        $CpuCores = (Get-WMIObject Win32_ComputerSystem).NumberOfLogicalProcessors
        $CPUProcesses = (Get-Counter "\Process(*)\% Processor Time" -SampleInterval 1 -MaxSamples 30 -ErrorAction SilentlyContinue).CounterSamples | Where-Object { $_.instancename -NotLike "_total" -and $_.instancename -NotLike "idle" } | Group-Object -Property Instancename | Select Name, @{Name = "Min"; Expression = { [Decimal]::Round((($_.group | Measure-Object CookedValue -Minimum).minimum / $CpuCores), 2) } }, @{Name = "Avg"; Expression = { [Decimal]::Round((($_.group | Measure-Object CookedValue -average).average / $CpuCores), 2) } }, @{Name = "Max"; Expression = { [Decimal]::Round((($_.group | Measure-Object CookedValue -maximum).maximum / $CpuCores), 2) } } | Sort-Object -Property Avg -Descending | Select-Object -First 10
        [string]$CPUResultString = $null
        foreach ($item in $CPUProcesses) {
            $CPUResultString += "Min:$($item.Min) Avg:$($item.Avg) Max:$($item.Max) - $($item.Name)<br />"
        }

        #------Get Machine memory------
        #---NOTE: May not be accuarte if Remote session uses Dynamic Memory------
        Write-host "getting Memory"
        $maxMemory = ((Get-WmiObject Win32_physicalMemory) | Measure-Object Capacity -Sum).sum / 1GB
        $consumedMemory = 0
        foreach ($WS in (get-process | select-object Name, @{Name = 'WorkingSet'; Expression = { ($_.WorkingSet64) } })) {
            $consumedMemory += $WS.WorkingSet
        }
        $consumedMemory = [math]::Round($consumedMemory / 1GB, 2)
        #top 10 RAM uses
        $RAMArray = @()
        $timer = 0
        While ($Timer -lt 10) {
            $RAMArray += $RAMTest = Get-Process | Group-Object -Property ProcessName | Select Name, @{Name = 'Memory_usage'; Expression = { [math]::Round((($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB), 2) } }
            Start-Sleep -seconds 1
            $timer ++
        }
        $RAMResult = $RAMArray | Group-Object -Property Name | Select Name, @{Name = 'Memory_usage'; Expression = { [math]::Round((($_.Group | Measure-Object "Memory_usage" -Average).Average), 2) } } | Sort-Object -Property 'Memory_usage' -Descending | select -first 10
        [string]$RAMResultString = $null
        foreach ($item in $RAMResult) {
            $RAMResultString += "$($item.Memory_usage)MB - $($item.Name)<br />"
        }

        $activityOutput.out.ProcessMemory = ($RAMResult | Out-String).Trim()
        $activityOutput.out.ProcessMemory = $RAMResultString
        $activityOutput.out.maxMemory = $maxMemory
        $activityOutput.out.consumedMemory = $consumedMemory

        #----Get Capacity and remaining space for disks----
        $allDisks = @()
        $diskCount = 0
        $Drives = Get-WmiObject Win32_Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -NotLike $Null -and $_.DriveType -eq "3" } | Select DriveLetter, @{Name = "Capacity"; Expression = { [math]::Round($_.capacity / 1GB, 2) } }, @{Name = "FreeSpace"; Expression = { [math]::Round($_.FreeSpace / 1GB, 2) } } | Sort-Object -Property FreeSpace -Descending
        [string]$DriveResultString = $null
        foreach ($item in $Drives) {
            $DriveResultString += "Drive: $($item.DriveLetter) - Capacity: $($item.Capacity)GB - Used: $($item.Capacity - $item.FreeSpace)GB - Free: $($item.FreeSpace)GB<br />"
        }

        $activityOutput.out.ProcessMemory = ($RAMResult | Out-String).Trim()

        $data = @{
            OSInfo          = $OSInfo;
            CPUInfo         = $CPUInfo;
            CPULoad         = $CPULoad;
            RAMHardwareInfo = $RAMHardwareInfo;
            DriveHardwareInfo = $DriveHardwareInfo;
            DriveResultString = $DriveResultString;
            VendorInfo      = $VendorInfo;
            GeneralSystemInfo = $GeneralSystemInfo;
            PowerInfo       = $PowerInfo;
            NetworkTypeInfo = $NetworkTypeInfo;
            ConsumedMemory  = $consumedMemory;
            NetworkInfo     = $objNetworkInfo;
            CPUProcesses    = $CPUResultString;
            RAMResult       = $RAMResultString;
            Hotfixes        = $hotfix;
        }

        Write-Host $(ConvertTo-Json $data)
        $activityOutput.out.data = $data

        [string]$OtherInfo = $null
        $OtherInfo += "Last Boot: $lastBootTimeAus`n"
        $OtherInfo += "Power Plan: $powerplan`n"
        $activityOutput.out.OtherInfo = $OtherInfo
    } catch {
        Write-Host $_.Exception.Message
    }
}

function Main {
    try {
        Write-Host "GetDebugDetails"
        GetDebugDetails
        Write-Host "GetUserDetails"
        $captureReturn3 = GetUserDetails
        Write-Host "GetMachineDetails"
        $captureReturn4 = GetMachineDetails
        $activityOutput.success = $true
    } catch {
        Write-Host $_.Exception.Message
    }
}

function Execute {
    try {
        $exec = Main
        return $activityOutput
    } catch {
        Write-Host $_.Exception.Message
    }
}

# Export functions
#endregion

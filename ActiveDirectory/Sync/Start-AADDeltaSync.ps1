function Start-AADDeltaSync {
    <#
    .SYNOPSIS
    Initiates a Delta Directory Sync on an Azure AD Connect Server.

    .DESCRIPTION
    This function automates synchronization between Azure AD and on-premises Active Directory.
    It checks the Azure AD Sync service status, starts it if necessary, and initiates a delta sync.

    .PARAMETER MaxWaitMinutes
    Maximum minutes to wait for synchronization to complete (default = 60)

    .EXAMPLE
    Start-AADDeltaSync -MaxWaitMinutes 30

    .OUTPUTS
    PSCustomObject with synchronization results including Success status and details
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$MaxWaitMinutes = 60
    )

    # Initialize output object
    $output = [PSCustomObject]@{
        Success            = $false
        AADServiceRunning  = $false
        SyncSuccessful     = $false
        Message            = ''
        FinalStatus        = ''
        ExecutionTime      = [datetime]::Now
    }

    # Function to check ADSync service status
    function Get-ADSyncServiceStatus {
        try {
            $service = Get-Service -Name 'ADSync' -ErrorAction Stop
            return [PSCustomObject]@{
                Status  = $service.Status
                Path    = (Get-WmiObject Win32_Service -Filter "Name='ADSync'").PathName
            }
        }
        catch {
            Write-Verbose "ADSync service not found"
            return $null
        }
    }

    # Function to start executable with error handling
    function Invoke-ADSyncExecutable {
        param($Path)
        try {
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo($Path)
            $processInfo.CreateNoWindow = $true
            $processInfo.UseShellExecute = $false
            $processInfo.RedirectStandardOutput = $true

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $processInfo
            $process.Start() | Out-Null
            $output = $process.StandardOutput.ReadToEnd()
            $process.WaitForExit()
            
            return [PSCustomObject]@{
                ExitCode = $process.ExitCode
                Output   = $output
            }
        }
        catch {
            Write-Verbose "Failed to execute $Path"
            return $null
        }
    }

    # Main synchronization logic
    try {
        # Check for Azure AD Connect wizard and terminate if running
        if (Get-Process -Name AzureADConnect -ErrorAction SilentlyContinue) {
            Write-Verbose "Stopping Azure AD Connect wizard process"
            Stop-Process -Name AzureADConnect -Force -ErrorAction Stop
        }

        # Load ADSync module
        $modulePath = "C:\Program Files\Microsoft Azure AD Sync\Bin\ADSync\ADSync.psd1"
        if (-not (Get-Module ADSync)) {
            if (Test-Path $modulePath) {
                Import-Module $modulePath -Force -ErrorAction Stop
                Write-Verbose "Successfully imported ADSync module"
            }
            else {
                throw "ADSync module not found at $modulePath"
            }
        }

        # Check service status
        $serviceStatus = Get-ADSyncServiceStatus
        if (-not $serviceStatus) {
            throw "ADSync service not found"
        }

        $output.AADServiceRunning = $serviceStatus.Status -eq 'Running'

        # Ensure service is running
        if ($serviceStatus.Status -ne 'Running') {
            Write-Verbose "Starting ADSync service"
            Start-Service -Name 'ADSync' -ErrorAction Stop
            $output.AADServiceRunning = $true
            Start-Sleep -Seconds 5  # Allow service startup time
        }

        # Wait for any existing sync to complete
        $scheduler = Get-ADSyncScheduler
        if ($scheduler.SyncCycleInProgress) {
            Write-Verbose "Existing sync in progress, waiting for completion..."
            $startWait = [DateTime]::Now
            while ($scheduler.SyncCycleInProgress -and 
                  ([DateTime]::Now - $startWait).TotalMinutes -lt $MaxWaitMinutes) {
                Start-Sleep -Seconds 15
                $scheduler = Get-ADSyncScheduler
            }
        }

        # Initiate delta sync
        Write-Verbose "Starting delta synchronization"
        Start-ADSyncSyncCycle -PolicyType Delta -ErrorAction Stop

        # Wait for sync completion
        $startTime = [DateTime]::Now
        while (([DateTime]::Now - $startTime).TotalMinutes -lt $MaxWaitMinutes) {
            $scheduler = Get-ADSyncScheduler
            if (-not $scheduler.SyncCycleInProgress) {
                $output.SyncSuccessful = $true
                $output.Success = $true
                $output.FinalStatus = 'Completed'
                return $output
            }
            Start-Sleep -Seconds 15
        }

        throw "Sync did not complete within $MaxWaitMinutes minutes"
    }
    catch {
        $output.Message = $_.Exception.Message
        $output.FinalStatus = 'Failed'
        $output.Success = $false
        return $output
    }
}

# Example usage:
# $result = Start-AADDeltaSync -MaxWaitMinutes 30 -Verbose
# $result | Format-List

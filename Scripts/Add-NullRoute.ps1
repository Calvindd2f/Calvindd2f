<# If you want a 1-liner then do
PS:> echo "127.0.0.1 example.com" >> "C:\WINDOWS\System32\drivers\etc\hosts"
#>
function Add-NullRoute {
    <#
    .SYNOPSIS
    Adds a null route entry to the Windows hosts file.
    
    .DESCRIPTION
    This function adds an entry to redirect the specified host to localhost (127.0.0.1 for IPv4 or ::1 for IPv6).
    
    .PARAMETER HostName
    The hostname or domain to be null routed.
    
    .PARAMETER IPv6
    Switch to use IPv6 (::1) instead of IPv4 (127.0.0.1).
    
    .PARAMETER Force
    Overwrites existing entries for the same hostname.
    
    .EXAMPLE
    Add-NullRoute -HostName "example.com"
    # Redirects example.com to 127.0.0.1
    
    .EXAMPLE
    Add-NullRoute -HostName "example.com" -IPv6
    # Redirects example.com to ::1
    
    .EXAMPLE
    Add-NullRoute -HostName "example.com" -Force
    # Updates any existing entry for example.com
    #>
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$HostName,
        
        [switch]$IPv6,
        
        [switch]$Force
    )
    
    begin {
        $hostsPath = "$env:windir\System32\drivers\etc\hosts"
        $ipAddress = if ($IPv6) { "::1" } else { "127.0.0.1" }
        $entry = "$ipAddress`t$HostName"
    }
    
    process {
        try {
            # Check if hosts file exists
            if (-not (Test-Path $hostsPath)) {
                Write-Warning "Hosts file not found at $hostsPath"
                return
            }
            
            # Get current content
            $content = Get-Content $hostsPath -Raw
            
            # Check if entry already exists
            $pattern = [regex]::Escape($HostName)
            $existingEntry = $content -match "(?m)^\s*(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|::1)\s+$pattern\s*$"
            
            if ($existingEntry -and $Force) {
                # Remove existing entry if Force is specified
                $content = $content -replace "(?m)^\s*(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|::1)\s+$pattern\s*$", ""
                $content = $content.Trim()
                $content += "`r`n$entry"
                Write-Verbose "Replaced existing entry for $HostName"
            }
            elseif ($existingEntry) {
                Write-Warning "Entry for $HostName already exists. Use -Force to overwrite."
                return
            }
            else {
                # Add new entry
                $content = $content.Trim()
                $content += "`r`n$entry"
                Write-Verbose "Added new entry for $HostName"
            }
            
            # Write changes (requires admin privileges)
            try {
                $content | Out-File $hostsPath -Encoding ASCII -Force
                Write-Host "Successfully added null route for $HostName to $ipAddress" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to write to hosts file. Try running as Administrator."
                return
            }
        }
        catch {
            Write-Error "An error occurred: $_"
        }
    }
    
    end {
        # Nothing to clean up
    }
}

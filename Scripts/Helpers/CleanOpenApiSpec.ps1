function Remove-FillerKeys {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        $node,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [string[]]$fillerKeys
    )

    try {
        Write-Debug "Starting Remove-FillerKeys on node type: $($node.GetType().FullName)"
        $removedCount = 0
        
        if ($node -is [System.Collections.IDictionary] -or $node.GetType().Name -eq 'OrderedDictionary') {
            # Handle both regular dictionaries and OrderedDictionary
            $keys = @($node.Keys)
            
            foreach ($key in $keys) {
                if ($fillerKeys -contains $key) {
                    Write-Debug "Removing filler key: $key"
                    $node.Remove($key)
                    $removedCount++
                    continue
                }
                
                if ($null -ne $node[$key]) {
                    Write-Debug "Processing nested node for key: $key"
                    $nestedCount = Remove-FillerKeys -node $node[$key] -fillerKeys $fillerKeys
                    $removedCount += $nestedCount
                }
            }
        }
        elseif ($node -is [System.Collections.IEnumerable] -and -not ($node -is [string])) {
            # Handle array-like objects
            foreach ($item in @($node)) {
                if ($null -ne $item) {
                    Write-Debug "Processing array item"
                    $nestedCount = Remove-FillerKeys -node $item -fillerKeys $fillerKeys
                    $removedCount += $nestedCount
                }
            }
        }
        
        Write-Verbose "Removed $removedCount filler keys from node"
        return $removedCount
    }
    catch {
        Write-Error "Error in Remove-FillerKeys: $($_.Exception.Message)"
        throw
    }
}

function Add-OperationIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        $paths
    )
    
    try {
        Write-Debug "Starting Add-OperationIds for paths"
        $addedCount = 0
        $missingCount = 0
        $httpMethods = @('get', 'post', 'put', 'delete', 'patch', 'options', 'head')
        
        # Track paths with missing operationIds
        $missingOperations = @()
        
        foreach ($path in $paths.Keys) {
            Write-Debug "Processing path: $path"
            
            # Handle if path value is null or not an object
            if ($null -eq $paths[$path] -or -not ($paths[$path] -is [PSObject])) {
                Write-Warning "Invalid path object at $path"
                continue
            }
            
            # Get all HTTP method operations for this path
            $methods = $paths[$path].PSObject.Properties | 
                Where-Object { $_.Name -in $httpMethods }
            
            if (-not $methods) {
                Write-Debug "No HTTP methods found for path: $path"
                continue
            }
            
            foreach ($method in $methods) {
                $op = $method.Value
                
                # Skip if operation is null or not an object
                if ($null -eq $op) {
                    Write-Warning "Null operation found for $($method.Name) $path"
                    continue
                }
                
                # Check if operationId exists and is not empty
                if (-not $op.PSObject.Properties['operationId'] -or 
                    [string]::IsNullOrWhiteSpace($op.operationId)) {
                    
                    Write-Debug "Generating operationId for $($method.Name) $path"
                    
                    # Create a more unique operationId
                    $pathParts = $path.Trim('/').Split('/')
                    $version = $pathParts | Where-Object { $_ -match 'v\d+' } | Select-Object -First 1
                    
                    # Sanitize path for operationId
                    $sanitizedPath = $path -replace '[{}\/]', '_'
                    $sanitizedPath = $sanitizedPath -replace '_+', '_'
                    $sanitizedPath = $sanitizedPath.Trim('_')
                    
                    # Include version in operationId if found
                    $operationId = if ($version) {
                        "$($method.Name)_${version}_$sanitizedPath"
                    } else {
                        "$($method.Name)_$sanitizedPath"
                    }
                    
                    # Ensure operationId is valid
                    $operationId = $operationId -replace '[^a-zA-Z0-9_]', '_'
                    $operationId = $operationId -replace '_+', '_'
                    $operationId = $operationId.Trim('_')
                    
                    $op.operationId = $operationId
                    $addedCount++
                    
                    Write-Debug "Added operationId: $operationId"
                } else {
                    Write-Debug "OperationId already exists: $($op.operationId)"
                }
                
                # Validate the operationId format
                if ($op.operationId -notmatch '^[a-zA-Z0-9_]+$') {
                    Write-Warning "Invalid operationId format: $($op.operationId) for $($method.Name) $path"
                    $missingOperations += "$($method.Name.ToUpper()) $path"
                    $missingCount++
                }
            }
        }
        
        # Report statistics
        Write-Verbose "Added $addedCount operation IDs"
        if ($missingCount -gt 0) {
            Write-Warning "Found $missingCount operations with invalid operationIds"
            Write-Warning "Operations with invalid IDs:`n$($missingOperations | ForEach-Object { "  $_" } | Join-String -Separator "`n")"
        }
        
        return @{
            Added = $addedCount
            Invalid = $missingCount
            MissingOperations = $missingOperations
        }
    }
    catch {
        Write-Error "Error in Add-OperationIds: $($_.Exception.Message)"
        throw
    }
}

function Truncate-LongDescriptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        $node,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 1000)]
        [int]$maxLength = 25
    )
    
    try {
        Write-Debug "Starting Truncate-LongDescriptions with maxLength: $maxLength"
        $truncatedCount = 0
        
        if ($node -is [System.Collections.IDictionary] -or $node.GetType().Name -eq 'OrderedDictionary') {
            if ($node.ContainsKey('description') -and $node['description'] -is [string]) {
                $desc = $node['description']
                if ($desc.Length -gt $maxLength) {
                    Write-Debug "Truncating description of length $($desc.Length)"
                    $node['description'] = $desc.Substring(0, $maxLength) + "..."
                    $truncatedCount++
                }
            }
            
            # Process nested nodes
            foreach ($key in @($node.Keys)) {
                if ($null -ne $node[$key]) {
                    $nestedCount = Truncate-LongDescriptions -node $node[$key] -maxLength $maxLength
                    $truncatedCount += $nestedCount
                }
            }
        }
        elseif ($node -is [System.Collections.IEnumerable] -and -not ($node -is [string])) {
            foreach ($item in @($node)) {
                if ($null -ne $item) {
                    $nestedCount = Truncate-LongDescriptions -node $item -maxLength $maxLength
                    $truncatedCount += $nestedCount
                }
            }
        }
        
        Write-Verbose "Truncated $truncatedCount descriptions"
        return $truncatedCount
    }
    catch {
        Write-Error "Error in Truncate-LongDescriptions: $($_.Exception.Message)"
        throw
    }
}

function Clean-OpenApiSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({
            if (-not (Test-Path $_)) {
                throw [System.IO.FileNotFoundException]::new("Input file not found: $_")
            }
            if (-not ($_ -match '\.(json|yaml|yml)$')) {
                throw [System.ArgumentException]::new("File must be JSON or YAML")
            }
            return $true
        })]
        [string]$inputPath,
        
        [Parameter(Mandatory = $true)]
        [ValidateScript({
            try {
                $parentDir = [System.IO.Path]::GetDirectoryName($_)
                if (-not (Test-Path $parentDir)) {
                    [System.IO.Directory]::CreateDirectory($parentDir)
                }
                return $true
            }
            catch {
                throw [System.IO.IOException]::new("Invalid output path: $_")
            }
        })]
        [string]$outputPath,
        
        [string[]]$fillerKeys = @('examples', 'x-code-samples', 'x-codeSamples', 'x-example', 'x-logo', 'x-samples', 'example', 'x-explorer-enabled', 'x-proxy-enabled', 'x-webhooks'),
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 1000)]
        [int]$maxDescriptionLength = 25
    )
    
    begin {
        $ErrorActionPreference = 'Stop'
        $ProgressPreference = 'Continue'
        Write-Verbose "Starting OpenAPI cleaning process..."
        
        try {
            Write-Progress -Activity "Processing OpenAPI Specification" -Status "Reading input file..." -PercentComplete 0
            $openapi = Get-Content $inputPath -Raw | ConvertFrom-Json -Depth 100
        }
        catch {
            Write-Error "Failed to read or parse input file: $($_.Exception.Message)"
            throw
        }
    }
    
    process {
        try {
            Write-Progress -Activity "Processing OpenAPI Specification" -Status "Removing filler content..." -PercentComplete 25
            $removedKeys = Remove-FillerKeys -node $openapi -fillerKeys $fillerKeys
            Write-Verbose "Removed $removedKeys filler keys"

            Write-Progress -Activity "Processing OpenAPI Specification" -Status "Adding operation IDs..." -PercentComplete 50
            $opIdStats = Add-OperationIds -paths $openapi.paths
            
            Write-Progress -Activity "Processing OpenAPI Specification" -Status "Truncating descriptions..." -PercentComplete 75
            $truncatedCount = Truncate-LongDescriptions -node $openapi -maxLength $maxDescriptionLength
            Write-Verbose "Truncated $truncatedCount descriptions"

            Write-Progress -Activity "Processing OpenAPI Specification" -Status "Saving output..." -PercentComplete 90
            $openapi | ConvertTo-Json -Depth 100 | Set-Content $outputPath

            # Output statistics
            Write-Host "`nOperation Summary:" -ForegroundColor Cyan
            Write-Host "  Filler Keys Removed: $removedKeys"
            Write-Host "  Operation IDs Added: $($opIdStats.Added)"
            Write-Host "  Invalid Operation IDs: $($opIdStats.Invalid)"
            Write-Host "  Descriptions Truncated: $truncatedCount"
            
            if ($opIdStats.Invalid -gt 0) {
                Write-Warning "Some operations have invalid or missing operationIds. Check the warnings above for details."
            }
        }
        catch {
            Write-Error "Error during processing: $($_.Exception.Message)"
            throw
        }
    }
    
    end {
        Write-Progress -Activity "Processing OpenAPI Specification" -Status "Complete" -PercentComplete 100 -Completed
        Write-Verbose "OpenAPI specification cleaned and saved to: $outputPath"
    }
}

# The functions will now show detailed information about their operation
Clean-OpenApiSpec -inputPath "C:\Users\c\Desktop\GoToConnect.json" -outputPath "$([environment]::CurrentDirectory)\output.json"
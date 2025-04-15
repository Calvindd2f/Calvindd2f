function Get-DomainFromTenantId {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantId
    )
    
    try {
        # Use the newer login.microsoftonline.com endpoint
        $uri = "https://login.microsoftonline.com/$TenantId/.well-known/openid-configuration"
        
        # Create HttpClient with proper disposal
        $httpClient = [System.Net.Http.HttpClient]::new()
        $httpClient.DefaultRequestHeaders.Accept.Clear()
        $httpClient.DefaultRequestHeaders.Accept.Add([System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new('application/json'))
        
        try {
            # Make async HTTP request
            $response = $httpClient.GetAsync($uri).GetAwaiter().GetResult()
            
            if (-not $response.IsSuccessStatusCode) {
                # Try the older endpoint as fallback
                $uri = "https://login.windows.net/$TenantId/.well-known/openid-configuration"
                $response = $httpClient.GetAsync($uri).GetAwaiter().GetResult()
            }
            
            $response.EnsureSuccessStatusCode()
            
            # Read response content
            $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $config = $content | ConvertFrom-Json
            
            # Try to extract the domain from multiple endpoints
            $domain = $null
            
            # Try issuer URL first
            if ($config.issuer) {
                $domain = $config.issuer -replace '^https://login.microsoftonline.com/([^/]+)/.*$', '$1'
            }
            
            # If that didn't work, try token endpoint
            if (-not $domain -or $domain -eq $config.issuer) {
                $domain = $config.token_endpoint -replace '^https://login.microsoftonline.com/([^/]+)/.*$', '$1'
            }
            
            # If still no match, try authorization endpoint
            if (-not $domain -or $domain -eq $config.token_endpoint) {
                $domain = $config.authorization_endpoint -replace '^https://login.microsoftonline.com/([^/]+)/.*$', '$1'
            }
            
            if (-not $domain -or $domain -eq $config.authorization_endpoint) {
                Write-Error "Could not extract domain from the response. Please verify the tenant ID is correct."
                return $null
            }
            
            return $domain
            
        } finally {
            # Properly dispose of the HttpClient
            $httpClient.Dispose()
        }
        
    } catch {
        Write-Error "Failed to retrieve domain for tenant ID $TenantId : $_"
        return $null
    }
}
function Get-TenantIdFromDomain {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )
    
    try {
        # Use the newer login.microsoftonline.com endpoint
        $uri = "https://login.microsoftonline.com/$Domain/.well-known/openid-configuration"
        
        # Create HttpClient with proper disposal
        $httpClient = [System.Net.Http.HttpClient]::new()
        $httpClient.DefaultRequestHeaders.Accept.Clear()
        $httpClient.DefaultRequestHeaders.Accept.Add([System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new('application/json'))
        
        try {
            # Make async HTTP request
            $response = $httpClient.GetAsync($uri).GetAwaiter().GetResult()
            
            if (-not $response.IsSuccessStatusCode) {
                # Try the older endpoint as fallback
                $uri = "https://login.windows.net/$Domain/.well-known/openid-configuration"
                $response = $httpClient.GetAsync($uri).GetAwaiter().GetResult()
            }
            
            $response.EnsureSuccessStatusCode()
            
            # Read response content
            $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $config = $content | ConvertFrom-Json
            
            # Extract the tenant ID from the issuer URL
            $issuerUrl = $config.issuer
            $TenantId = $issuerUrl -replace '^https://login.microsoftonline.com/([^/]+)/.*$', '$1'
            
            # If the first extraction didn't work, try the token endpoint
            if (-not $TenantId -or $TenantId -eq $issuerUrl) {
                $TenantId = $config.token_endpoint -replace '^https://login.microsoftonline.com/([^/]+)/.*$', '$1'
            }
            
            # If still no match, try the authorization endpoint
            if (-not $TenantId -or $TenantId -eq $config.token_endpoint) {
                $TenantId = $config.authorization_endpoint -replace '^https://login.microsoftonline.com/([^/]+)/.*$', '$1'
            }
            
            if (-not $TenantId -or $TenantId -eq $config.authorization_endpoint) {
                Write-Error "Could not extract Tenant ID from the response. Please verify the domain is correct."
                return $null
            }
            
            return $TenantId
            
        } finally {
            # Properly dispose of the HttpClient
            $httpClient.Dispose()
        }
        
    } catch {
        Write-Error "Failed to retrieve Tenant ID for domain $Domain : $_"
        return $null
    }
}
function Get-TenantIdFromSubscriptionId {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        [Parameter(Mandatory = $false)]
        [string]$AccessToken
    )
    
    try {
        # This endpoint requires authentication
        $uri = "https://management.azure.com/subscriptions/$SubscriptionId`?api-version=2020-01-01"
        
        # Create HttpClient with proper disposal
        $httpClient = [System.Net.Http.HttpClient]::new()
        $httpClient.DefaultRequestHeaders.Accept.Clear()
        $httpClient.DefaultRequestHeaders.Accept.Add([System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new('application/json'))
        
        if ($AccessToken) {
            $httpClient.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $AccessToken)
        }
        
        try {
            $uri = "https://management.azure.com/subscriptions/$SubscriptionId`?api-version=2020-01-01"

            $response = $httpClient.GetAsync($uri).GetAwaiter().GetResult()
            
            if ($response.IsSuccessStatusCode) {
                $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                $result = $content | ConvertFrom-Json
                return $result.tenantId
            } else {
                # If we get a 401, try to extract tenant ID from WWW-Authenticate header
                if ($response.StatusCode -eq [System.Net.HttpStatusCode]::Unauthorized) {
                    if ($response.Headers -and $response.Headers.WwwAuthenticate) {
                        $authHeader = $response.Headers.WwwAuthenticate.ToString()
                        if ($authHeader -match 'authorization_uri="https://login.windows.net/([^"]+)"') {
                            return $matches[1]
                        }
                    }
                }
                Write-Error "Failed to get subscription details. Status code: $($response.StatusCode)"
                return $null
            }
        } finally {
            $httpClient.Dispose()
        }
        
    } catch {
        Write-Error "Failed to retrieve tenant ID: $_"
        return $null
    }
}

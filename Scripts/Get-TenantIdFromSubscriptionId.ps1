function Get-TenantIdFromSubscription {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )
    
    try {
        # This public endpoint can resolve subscription to tenant without authentication
        $uri = "https://management.azure.com/subscriptions/$SubscriptionId?api-version=2020-01-01"
        
        # Create HttpClient with proper disposal
        $httpClient = [System.Net.Http.HttpClient]::new()
        $httpClient.DefaultRequestHeaders.Accept.Clear()
        $httpClient.DefaultRequestHeaders.Accept.Add([System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new('application/json'))
        
        try {
            # Create HTTP request
            $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $uri)
            
            # Make async HTTP request
            $response = $httpClient.SendAsync($request).GetAwaiter().GetResult()
            
            if ($response.IsSuccessStatusCode) {
                # Read response content
                $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                $result = $content | ConvertFrom-Json
                return $result.tenantId
            } else {
                # Parse the error to extract tenant ID if possible
                if ($response.Headers -and $response.Headers.WwwAuthenticate) {
                    $authHeader = $response.Headers.WwwAuthenticate.ToString()
                    if ($authHeader -match 'authorization_uri="https://login.windows.net/([^"]+)"') {
                        return $matches[1]
                    }
                }
                $response.EnsureSuccessStatusCode() # This will throw if we haven't found the tenant ID
            }
        } finally {
            # Properly dispose of the HttpClient and request
            $request?.Dispose()
            $httpClient.Dispose()
        }
        
    } catch {
        Write-Error "Failed to retrieve tenant ID: $_"
        return $null
    }
}

function Get-DomainFromTenantId {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantId
    )
    
    try {
        # This public endpoint can resolve tenant information without authentication
        $uri = "https://login.windows.net/$TenantId/.well-known/openid-configuration"
        
        # Create HttpClient with proper disposal
        $httpClient = [System.Net.Http.HttpClient]::new()
        $httpClient.DefaultRequestHeaders.Accept.Clear()
        $httpClient.DefaultRequestHeaders.Accept.Add([System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new('application/json'))
        
        try {
            # Make async HTTP request
            $response = $httpClient.GetAsync($uri).GetAwaiter().GetResult()
            $response.EnsureSuccessStatusCode()
            
            # Read response content
            $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $config = $content | ConvertFrom-Json
            
            # Extract the domain from the issuer URL
            $issuerUrl = $config.issuer
            $domain = $issuerUrl -replace '^https://login.microsoftonline.com/([^/]+)/.*$', '$1'
            
            # For some tenants, this might be the tenant ID again, so try alternative approach
            if ($domain -eq $TenantId) {
                $domain = $config.token_endpoint -replace '^https://login.microsoftonline.com/([^/]+)/.*$', '$1'
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

Function Get-AccessToken {
    [Alias('GetAccessToken', 'Get-Token')]

    Param(
        [string]$appId = $env:appId,
        [string]$secret = $env:secret,
        [string]$tenantId = $env:tenantId,
        [switch]$print
    )

    Begin {

        # Return Boilerplate
        $variableProps = @{ access_token = $null; };
        $outputProps = @{ out = $(New-Object psobject -Property $variableProps)}
        $activityOutput = [psobject]::new($outputProps);

        # Define the token endpoint URL
        $tokenUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"

        # Define the body of the request
        $body = @{
            client_id     = $appId
            scope         = "https://graph.microsoft.com/.default"
            client_secret = $secret
            grant_type    = "client_credentials"
        }
    }

    Process {
        # Convert the body to URL-encoded form data
        $formData = $body.GetEnumerator() | ForEach-Object { "$($_.Key)=$([System.Web.HttpUtility]::UrlEncode($_.Value))" }
        $formDataString = $formData -join "&"

        # Inline C# code to make an asynchronous HTTP POST request
        Add-Type -TypeDefinition @"
using System;
using System.Net.Http;
using System.Threading.Tasks;
using System.Text;

public class TokenRequester
{
    private static readonly HttpClient httpClient = new HttpClient();

    public static async Task<string> GetAccessTokenAsync(string url, string formData)
    {
        var content = new StringContent(formData, Encoding.UTF8, "application/x-www-form-urlencoded");
        HttpResponseMessage response = await httpClient.PostAsync(url, content);
        response.EnsureSuccessStatusCode();
        string responseBody = await response.Content.ReadAsStringAsync();
        return responseBody;
    }
}
"@ -Language CSharp

        # Call the C# method asynchronously and get the result
        $task = [TokenRequester]::GetAccessTokenAsync($tokenUrl, $formDataString)
        $task.Wait()  # Wait for the async task to complete
        $response = $task.Result
    }

    End {
        if([switch]$print)
        {
            # Output the access token
            $response
        }

        $access_token = ($response | ConvertFrom-Json).access_token

        $activityOutput.out.access_token = $access_token
        return $activityOutput
    }

}

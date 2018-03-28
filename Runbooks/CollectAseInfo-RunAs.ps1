<#
.SYNOPSIS

.DESCRIPTION

.NOTES

.LINK
.EXAMPLE
#>

$ErrorActionPreference = 'Continue'
 
$startTime = Get-Date

$clientId       =  Get-AutomationVariable -Name 'clientId'
$clientSecret   = Get-AutomationVariable -Name 'clientSecret'
$tenantId      = Get-AutomationVariable -Name 'tenantId'
$workspaceId = Get-AutomationVariable -Name 'workspaceId'
$SharedKey = Get-AutomationVariable -Name 'workspaceKey'
$hostingEnvironmentRG = Get-AutomationVariable -Name 'hostingEnvironmentRG'
$hostingEnvironmentName = Get-AutomationVariable -Name 'hostingEnvironmentName'
$subscriptionId = Get-AutomationVariable -Name 'subscriptionId'

# Specify the name of the record type that you'll be creating
$LogType = "AseData"

# Specify a field with the created time for the records
$TimeStampField = "DateValue"

# Service Principal Credentials
# We are not using the RunAs Account
$password = $clientSecret | ConvertTo-SecureString -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $clientId, $password 

"Login to the tenant"
Add-AzureRmAccount -Credential $credential -ServicePrincipal -TenantId $tenantId -Subscription $subscriptionId

$tokenEndpoint = {https://login.windows.net/{0}/oauth2/token} -f $tenantId 
$armUri = "https://management.azure.com/";

$body = @{
        'resource'= $armUri
        'client_id' = $clientId
        'grant_type' = 'client_credentials'
        'client_secret' = $clientSecret
}

$params = @{
    ContentType = 'application/x-www-form-urlencoded'
    Headers = @{'accept'='application/json'}
    Body = $body
    Method = 'Post'
    URI = $tokenEndpoint
}

$token = Invoke-RestMethod @params

 $header = @{
     'Content-Type'='application\json'
     'Authorization'='Bearer ' + $token.access_token
 }

$RunbookName = ""

$apiVersion = "2016-09-01"
$method = "GET"

$contentType = "application/json"
$manageUrl = "https://management.core.windows.net/"
$rmUrl = "https://management.azure.com/"

# Create the function to create the authorization signature
Function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource)
{
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)

    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
    return $authorization
}


# Create the function to create and post the request
Function Post-LogAnalyticsData($customerId, $sharedKey, $body, $logType)
{
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -customerId $customerId `
        -sharedKey $sharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -fileName $fileName `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
        "time-generated-field" = $TimeStampField;
    }

    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing 
    return $response

}

"Getting the ASE Resource"
$he = Find-azurermresource -ResourceType "Microsoft.Web/hostingEnvironments" -ResourceGroupNameEquals $hostingEnvironmentRG -ResourceNameEquals $hostingEnvironmentName

if (-not $he) { throw "No hosting environment found"}

"Processing $($he.Name)"

$data = [ordered]@{
    "TenantId"= "$tenantId"
    "ResourceProvider"= $he.ResourceType
    "ResourceGroupName"= "$($he.ResourceGroupName)"
    "QueryDate"= "$((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"))"
    "EventDataId"= "$((New-Guid).ToString())"
}
$obj = New-Object -Type PSObject -Property $data

#lets get the ase data
"Retrieving ase info"
$uri = $rmUrl  + "subscriptions/$subscriptionId/resourceGroups/$($he.ResourceGroupName)/providers/Microsoft.Web/hostingEnvironments/$($he.Name)?api-version=$apiVersion"

$sw = [system.diagnostics.stopwatch]::startNew()
$response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $header -ErrorAction SilentlyContinue -UseBasicParsing

if ($response.StatusCode -eq 200)
{
    $data = ($response.Content | ConvertFrom-Json).properties
    foreach ($item in (get-member -InputObject $data -MemberType NoteProperty)){   
           
        $val=$data | Select-Object -ExpandProperty $item.Name   
        $obj | Add-Member -Name $item.Name -MemberType NoteProperty -Value $val
    }
    $obj | add-member Noteproperty AseInfoResponseFail $false
}
else
{
    $obj | add-member Noteproperty AseInfoResponseFail $true
}
$data | add-member Noteproperty AseInfoResponseTimeMs $sw.Elapsed.Milliseconds

# Get the outbound for the hosting environment
"Retrieving outbound rules"
$sw = [system.diagnostics.stopwatch]::startNew()
$uri = $rmUrl  + "subscriptions/$subscriptionId/resourceGroups/$($he.ResourceGroupName)/providers/Microsoft.Web/hostingEnvironments/$($he.Name)/outboundnetworkdependenciesendpoints?api-version=$apiVersion"
$response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $header -UseBasicParsing

if ($response.StatusCode -eq 200)
{
    $outbound = ($response.Content | ConvertFrom-Json).value
    foreach ($item in $outbound)
    {
        $obj | add-member Noteproperty ($item.description -replace " ", "") ($item.endpoints -join ",")
        $obj | add-member Noteproperty "$($item.description -replace ' ', '')Cnt" $item.endpoints.Count
    }

    $obj | add-member Noteproperty OutboundResponseFail $false
}
else
{
    $obj | add-member Noteproperty OutboundResponseFail $true
}
$obj | add-member Noteproperty OutboundResponseTimeMs $sw.Elapsed.Milliseconds

"Retrieving inbound rules"
$sw = [system.diagnostics.stopwatch]::startNew()
$uri = $rmUrl  + "subscriptions/$subscriptionId/resourceGroups/$($he.ResourceGroupName)/providers/Microsoft.Web/hostingEnvironments/$($he.Name)/inboundnetworkdependenciesendpoints?api-version=$apiVersion"
$response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $header -UseBasicParsing
$content = $response.Content | ConvertFrom-Json

if ($response.StatusCode -eq 200)
{
    $inbound = ($response.Content | ConvertFrom-Json).value
    foreach ($item in $inbound)
    {
        $obj | add-member Noteproperty ($item.description -replace ' ', '') ($item.endpoints -join ",")
        $obj | add-member Noteproperty "$($item.description -replace ' ', '')Cnt" $item.endpoints.Count
    }

    $obj | add-member Noteproperty InboundResponseFail $false
}
else
{
    $obj | add-member Noteproperty InboundResponseFail $true
}
$obj | add-member Noteproperty InboundResponseTimeMs $sw.Elapsed.Milliseconds
    
$obj | add-member Noteproperty RuntimeSeconds (NEW-TIMESPAN –Start $startTime –End (Get-Date)).TotalSeconds

$json = $obj | ConvertTo-Json

"Posting data to OMS Workspace"
$response = Post-LogAnalyticsData -customerId $workspaceId -sharedKey $sharedKey -body ([System.Text.Encoding]::UTF8.GetBytes($json)) -logType $LogType
if ($response.StatusCode -eq 200)
{
    "Success"
}
else
{
    throw "Failed"
}

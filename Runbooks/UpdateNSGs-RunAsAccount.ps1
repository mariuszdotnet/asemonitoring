<#
.SYNOPSIS

.DESCRIPTION

.NOTES

.LINK
.EXAMPLE
#>


$ErrorActionPreference = 'Continue'
 
$nsgRgName=Get-AutomationVariable -Name 'nsgRG'
$nsgName=Get-AutomationVariable -Name 'nsgName'
$location= Get-AutomationVariable -Name 'location'

$clientId       =  Get-AutomationVariable -Name 'clientId'
$clientSecret   = Get-AutomationVariable -Name 'clientSecret'
$tenantId      = Get-AutomationVariable -Name 'tenantId'
$workspaceId = Get-AutomationVariable -Name 'workspaceId'
$SharedKey = Get-AutomationVariable -Name 'workspaceKey'
$hostingEnvironmentRG = Get-AutomationVariable -Name 'hostingEnvironmentRG'
$hostingEnvironmentName = Get-AutomationVariable -Name 'hostingEnvironmentName'
$subscriptionId = Get-AutomationVariable -Name 'subscriptionId'


$startTime = Get-Date

# Specify the name of the record type that you'll be creating
$LogType = "AseAuditData"

# Specify a field with the created time for the records
$TimeStampField = "DateValue"


$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}
Set-AzureRmContext -SubscriptionId $subscriptionId -TenantId $tenantID

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

function AddNSGRule ($ips, $name, $direction, $priority, $portRange) {
  
  if ($direction -eq "outbound")
  {
        $ruleName="$name-$direction"
        $nsg | Add-AzureRmNetworkSecurityRuleConfig -Name $ruleName -Description $name -Access Allow -Protocol * -Direction $direction -Priority $priority `
            -SourceAddressPrefix VirtualNetwork -SourcePortRange * `
            -DestinationAddressPrefix $ips -DestinationPortRange $portRange
  }
  else
  {
        $ruleName="$name-$direction"
        $nsg | Add-AzureRmNetworkSecurityRuleConfig -Name $ruleName -Description $name -Access Allow -Protocol * -Direction $direction -Priority $priority `
            -SourceAddressPrefix $ips -SourcePortRange * `
            -DestinationAddressPrefix VirtualNetwork -DestinationPortRange $portRange
  }
}

"Getting the ASE Resource"
$he = Get-AzureRmResource -ResourceType "Microsoft.Web/hostingEnvironments" -ResourceGroup $hostingEnvironmentRG -ResourceName $hostingEnvironmentName

if (-not $he) { throw "No hosting environment found"}

"Processing $($he.Name)"

$data = [ordered]@{
    "TenantId"= "$tenantId"
    "SubscriptionId"= "$subscriptionId"
    "ResourceProvider"= $he.ResourceType
    "ResourceGroupName"= "$($he.ResourceGroupName)"
    "QueryDate"= "$((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"))"
    "EventDataId"= "$((New-Guid).ToString())"
}
$obj = New-Object -Type PSObject -Property $data


# Get the outbound for the hosting environment
"Retrieving outbound rules"
$sw = [system.diagnostics.stopwatch]::startNew()
$uri = $rmUrl  + "subscriptions/$subscriptionId/resourceGroups/$($he.ResourceGroupName)/providers/Microsoft.Web/hostingEnvironments/$($he.Name)/outboundnetworkdependenciesendpoints?api-version=$apiVersion"
$response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $header -UseBasicParsing

if ($response.StatusCode -eq 200)
{
    $outbound = ($response.Content | ConvertFrom-Json).value
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
    $obj | add-member Noteproperty InboundResponseFail $false
}
else
{
    $obj | add-member Noteproperty InboundResponseFail $true
}
$obj | add-member Noteproperty InboundResponseTimeMs $sw.Elapsed.Milliseconds

"Getting Nsg Configuration"
$nsgStatus = "Consistent"
$nsgCreated = $false
$aseChanged = $false

$nsg = Get-AzureRmNetworkSecurityGroup -ResourceGroupName $nsgRgName -Name $nsgName -ErrorAction SilentlyContinue
if (-not $nsg)
{
    "Creating Nsg Config"
    $nsg = New-AzureRmNetworkSecurityGroup -ResourceGroupName $nsgRgName -Name $nsgName -Location $location -ErrorAction "Stop"
    $nsgStatus = "Created"
    $nsgCreated = $true
}

# nsg already existed, is it different from the ase results
if (-not $nsgCreated)
{
    "Checking for changes"
    "App Service Environment"
    foreach ($in in $inbound | where "description" -eq "App Service management")
    {    
        $rule = "$($in.description -replace ' ', '-')-Inbound"
        $nsgRule = $nsg.SecurityRules | Where-Object { $_.Name -eq $rule}
        if (-not $nsgRule){
            $aseChanged = $true
        }
        else
        {
           $comp = Compare-Object -DifferenceObject ($nsgRule.SourceAddressPrefix | Sort-Object) -ReferenceObject ($in.endpoints | Sort-Object)
           $aseChanged = $aseChanged -or (-not -not $comp)
           if ($aseChanged) {"$rule Changed"}
        }

        $rule = "$($in.description -replace ' ', '-')-Outbound"
        $nsgRule = $nsg.SecurityRules | Where-Object { $_.Name -eq $rule}
        if (-not $nsgRule){
            $aseChanged = $true
        }
        else
        {
           $comp = Compare-Object -DifferenceObject ($nsgRule.DestinationAddressPrefix | Sort-Object) -ReferenceObject ($in.endpoints | Sort-Object)
           $aseChanged = $aseChanged -or (-not -not $comp)
           if ($aseChanged) {"$rule Changed"; $comp}
        }

    }

    "Azure Management"
    foreach ($out in $outbound | where "description" -eq "Azure Management")
    {    
        $rule = "$($out.description -replace ' ', '-')-Inbound"
        $nsgRule = $nsg.SecurityRules | Where-Object { $_.Name -eq $rule}
        if (-not $nsgRule){
            $aseChanged = $true
        }
        else
        {
           $comp = Compare-Object -DifferenceObject ($nsgRule.SourceAddressPrefix | Sort-Object) -ReferenceObject ($out.endpoints | Sort-Object)
           $aseChanged = $aseChanged -or (-not -not $comp)
           if ($aseChanged) {"$rule Changed"}
        }

        $rule = "$($out.description -replace ' ', '-')-Outbound"
        $nsgRule = $nsg.SecurityRules | Where-Object { $_.Name -eq $rule}
        if (-not $nsgRule){
            $aseChanged = $true
        }
        else
        {
           $comp = Compare-Object -DifferenceObject ($nsgRule.DestinationAddressPrefix | Sort-Object) -ReferenceObject ($out.endpoints | Sort-Object)
           $aseChanged = $aseChanged -or (-not -not $comp)
           if ($aseChanged) {"$rule Changed"; $comp}
        }

    }
}

if ($nsgCreated -or $aseChanged)
{
    "Applying Nsg Rules"
    $nsgStatus = "Changed"
    $nsg.SecurityRules.Clear()
    
    $p=100 #Starting priority number
    AddNSGRule -ips ($inbound | where description -eq "App Service management" | select endpoints -ExpandProperty endpoints) -regionCode $regionCode -name "App-Service-Management" -priority $p -direction "Outbound" -portRange "*"

    $p=$p+50
    AddNSGRule -ips ($outbound | where description -eq "Azure management" | select endpoints -ExpandProperty endpoints) -regionCode $regionCode -name "Azure-Management" -priority $p -direction "Outbound" -portRange "*"

    # this is for the metrics
    $p=$p+50
    AddNSGRule -ips @("104.45.230.69/32") -regionCode $regionCode -name "Metrics" -priority $p -direction "Outbound" -portRange "*"


    $p=1000
    $ruleName="Ase-Deny-Outbound"
    $desc="DenyOutboundInternetfromASE"
    $nsg | Add-AzureRmNetworkSecurityRuleConfig -Name $ruleName -Description $desc -Access Deny -Protocol * -Direction "Outbound" -Priority $p `
        -SourceAddressPrefix VirtualNetwork -SourcePortRange * `
        -DestinationAddressPrefix Internet -DestinationPortRange * | Out-Null
 
    $p=100
    AddNSGRule -ips ($inbound | where description -eq "App Service management" | select endpoints -ExpandProperty endpoints) -regionCode $regionCode -name "App-Service-Management" -priority $p -direction "Inbound" -portRange "454-455"

    $p=150
    AddNSGRule -ips ($outbound | where description -eq "Azure management" | select endpoints -ExpandProperty endpoints) -regionCode $regionCode -name "Azure-Management" -priority $p -direction "Inbound" -portRange "454-455"

    $nsg
    $nsg | Set-AzureRmNetworkSecurityGroup -ErrorAction Stop
    $nsg
}

$obj | add-member Noteproperty AseName $he.Name
$obj | add-member Noteproperty AseResourceGroupName $he.ResourceGroupName
$obj | add-member Noteproperty NsgName $nsgName
$obj | add-member Noteproperty NsgResourceGroup $nsgRgName
$obj | add-member Noteproperty NsgStatus $nsgStatus
$obj | add-member Noteproperty NsgSubnets $nsgRgName
$obj | add-member Noteproperty NsgSubnetCount $nsg.Subnets.Count
$obj | add-member Noteproperty NsgInterfaceCount $nsg.NetworkInterfaces.Count
$obj | add-member Noteproperty AseChanges $aseChanged
$obj | add-member Noteproperty NsgCreated $nsgCreated

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

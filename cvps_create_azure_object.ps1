##### Script created on 11/29/2023 by Mark Richardson (Commvault Professional Services) #####
### Latest Update: 12/1/2023 ###

# This script will create a credential and instance for Azure File and Azure Blob in Commvault using the REST API
# The script will read from a csv file called input_object.csv
# The csv file should be in the same directory as the script
# The csv file should have the following columns: name, key, servicePrincipal. name is the storage account name, key is the storage account key, and servicePrincipal is the name of the service principal credential in Commvault
# The script will loop through each line in the csv file and create a credential for file and instance for Azure File and Azure Blob
# The script will use a pre-existing service principal cred for blob. It should exist already in Commvault
# The script will output a log file in the same directory as the script
# Need to set the $planName and $accessNodes variables below
# Need to set the $commserve variable below
# Domain user credentials should be in format username@domain

#### Updates (12/1/2023) ####
# Changed get Plan ID logic to get name instead of description
# Added line for self-signed certificates
# Changed URL for credential URL to webserver as after updating from 11.32.8 to 11.32.28 the normal URL stopped working

# Ignore SSL errors if using a self-signed certificate. Otherwise comment out the line below.
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

# Setup logging. This will create a log file in the same directory as the script
$Logfile = ".\cvps_create_azure_object.log"

# Set variables for Plan Name and Access Nodes Group
$planName = "Basic30_Day"
$accessNodes = "AccessNodeGroup"

# Set CommServe hostname
$commserve = "commserve1.cv.lab"

# Function to write to the log file
function WriteLog
{

    Param ([string]$LogString)
    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $LogMessage = "$Stamp $LogString"
    Add-content $LogFile -value $LogMessage

}

# Let's get credentials from the user to login to Commvault. Needs to be an admin
$credential = Get-Credential
$username = $credential.UserName
$password = $credential.GetNetworkCredential().password

# password needs to be in base64 format
$password = [System.Text.Encoding]::UTF8.GetBytes($password)
$password = [System.Convert]::ToBase64String($password)

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Accept", "application/json")
$headers.Add("Content-Type", "application/json")
$body = "{`n  `"password`": `"$password`",`n  `"username`": `"$username`",`n  `"timeout`" : 30`n}"

# Login
$response = Invoke-RestMethod "http://$commserve/webconsole/api/Login" -Method 'POST' -Headers $headers -Body $body
WriteLog "Login response: $response"

# need to extract the token
$token = $response | Select-Object -ExpandProperty token
# the first five characters need to be removed to get just the token
$token = $token.substring(5)

# Now that we have a token we can do things
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Accept", "application/json")
$headers.Add("Authtoken", "$token")
$headers.Add("Content-Type", "application/json")

# Get the Plan ID

$response = Invoke-RestMethod "http://$commserve/webconsole/api/Plan" -Method 'GET' -Headers $headers
#$response
writeLog "Plan response: $response"
#$plan = $response.plans | Where-Object { $_.description -eq $planName}
$plan = $response.plans.plan | Where-Object planName -eq $planName
if ($plan) {
    # Access the specific data within the plan object
    #$planId = $plan.plan.planId
    $planId = $plan.planId
    #$planId
} else {
    Write-Host "Plan not found."
}

# Get the Client Group ID
$response = Invoke-RestMethod "http://$commserve/webconsole/api/ClientGroup" -Method 'GET' -Headers $headers

# Accessing the "groups" array
$groups = $response.groups

#Loop through the groups to find the one we want that matches $accessNodes
foreach ($group in $groups) {
    if ($group.name -eq $accessNodes) {
        $groupId = $group.Id
    }
}

# get the storage account name, key, and service principal from input_object.csv and store as variables. Also loop through each line in the csv
$csv = Import-Csv -Path ".\input_object.csv"
WriteLog "Imported CSV file $csv"

# Create the credential for Azure File.

foreach ($line in $csv) {
    $saName = $line.name
    $saKey = $line.key
    # convert the key to base64
    $saKey = [System.Text.Encoding]::UTF8.GetBytes($saKey)
    $saKey = [System.Convert]::ToBase64String($saKey)
    $servicePrincipal = $line.servicePrincipal

    # Get the Service Principal ID
    #$response = Invoke-RestMethod "https://$commserve/commandcenter/api/V4/Credential" -Method 'GET' -Headers $headers
    $response = Invoke-RestMethod "http://${commserve}:81/SearchSvc/CVWebService.svc/V4/Credential" -Method 'GET' -Headers $headers
    #loop through the credentials to find the one we want that matches $servicePrincipal
    foreach ($credential in $response.credentialManager) {
        if ($credential.name -eq $servicePrincipal) {
            $servicePrincipalId = $credential.id
        }
    }

    $credName = "$saName-key"
    $fileName = "$saName-file"
    $blobName = "$saName-blob"

    $jsonPre = @()
    $jsonPre = [PSCustomObject]@{
        accountType = "CLOUD_ACCOUNT"
        vendorType = "MICROSOFT_AZURE_TYPE"
        authType = "MICROSOFT_AZURE"
        name = $credName
        accountName = $saName
        accessKeyId = $saKey
        description = $credName
    }
    
    $body = $jsonPre | ConvertTo-Json -Depth 10

    #capture error in $response with try/catch
    try {
        $response = Invoke-RestMethod "https://$commserve/commandcenter/api/V4/Credential" -Method 'POST' -Headers $headers -Body $body -ContentType 'application/json'
        $credId = $response.id
        WriteLog "Created Credential: $response"
        Write-Host "Created Credential: $response"
    }
    catch {
        WriteLog "Error creating credential: $_"
        Write-Host "Error creating credential: $_"
        #if the credential already exists for file, get the credential id
        #$response = Invoke-RestMethod "https://$commserve/commandcenter/api/V4/Credential" -Method 'GET' -Headers $headers
        $response = Invoke-RestMethod "http://${commserve}:81/SearchSvc/CVWebService.svc/V4/Credential" -Method 'GET' -Headers $headers
        foreach ($credential in $response.credentialManager) {
            if ($credential.name -eq $credName) {
                $credId = $credential.id
                writelog "Cred id: $credId"
            }
        }
    }

    # create the Azure File instance
    $jsonPre = @()
    $jsonPre = [PSCustomObject]@{
        clientInfo = @{
            clientType = 15
            cloudClonnectorProperties = @{
                instanceType = "AZURE_BLOB"
                instance = @{
                    instance = @{
                        instanceName = $fileName
                        commCellId = 2
                        applicationId = 134
                    }
                    cloudAppsInstance = @{
                        instanceTypeDisplayName = "Azure File"
                        instanceType = "AZURE_BLOB"
                        generalCloudProperties = @{
                            numberOfBackupStreams = 4
                            memberServers = @(
                                @{
                                    client = @{
                                        clientGroupId = $groupId
                                        clientGroupName = $accessNodes
                                        _type_ = 28
                                    }
                                }
                            )
                            credentials = @{
                                credentialId = $credId
                                credentialName = $credName
                            }
                        }
                        azureInstance = @{
                            hostURL = "file.core.windows.net"
                        }
                        credentialType = "MICROSOFT_AZURE"
                    }
                    useResourcePoolInfo = $false
                }
            }
            plan = @{
                planId = $planId
                planName = $planName
            }
        }
        entity = @{
            clientName = $fileName
        }
    }

    $body = $jsonPre | ConvertTo-Json -Depth 10

    #capture error in $response with try-catch
        try {
            $response = Invoke-RestMethod "https://$commserve/commandcenter/api/Client" -Method 'POST' -Headers $headers -Body $body -ContentType 'application/json'
            writeLog "Created Azure File Object Client: $response for storage account $saName"
            Write-Host "Created Azure File Object Client: $response for storage account $saName"
        }
        catch {
            WriteLog "Error creating Azure File Client: $_"
            Write-Host "Error creating Azure File Client: $_"
        }

        # create the Azure Blob instance
        $jsonPre = @()
        $jsonPre = [PSCustomObject]@{
            clientInfo = @{
                clientType = 15
                cloudClonnectorProperties = @{
                    instanceType = "AZURE_BLOB"
                    instance = @{
                        instance = @{
                            instanceName = $blobName
                            commCellId = 2
                            applicationId = 134
                        }
                        cloudAppsInstance = @{
                            instanceTypeDisplayName = "Azure Blob"
                            instanceType = "AZURE_BLOB"
                            generalCloudProperties = @{
                                numberOfBackupStreams = 4
                                memberServers = @(
                                    @{
                                        client = @{
                                            clientGroupId = $groupId
                                            clientGroupName = $accessNodes
                                            _type_ = 28
                                        }
                                    }
                                )
                                credentials = @{
                                    credentialId = $servicePrincipalId
                                    credentialName = $servicePrincipal
                                }
                            }
                            azureInstance = @{
                                hostURL = "blob.core.windows.net"
                                adAccountName = $saName
                            }
                            credentialType = "AZUREACCOUNT"
                        }
                        useResourcePoolInfo = $false
                    }
                }
                plan = @{
                    planId = $planId
                    planName = $planName
                }
            }
            entity = @{
                clientName = $blobName
            }
        }

        $body = $jsonPre | ConvertTo-Json -Depth 10

        #capture error in $response with try-catch
        try {
            $response = Invoke-RestMethod "https://$commserve/commandcenter/api/Client" -Method 'POST' -Headers $headers -Body $body -ContentType 'application/json'
            writeLog "Created Azure Blob Object Client: $response for storage account $saName"
            Write-Host "Created Azure Blob Object Client: $response for storage account $saName"
        }
        catch {
            WriteLog "Error creating Azure Blob Client: $_"
            Write-Host "Error creating Azure Blob Client: $_"
        }
        
    }


















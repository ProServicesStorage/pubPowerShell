
### Created by Mark Richardson - Commvault Professional Services on 12/1/2023 ###

### Description ###
# This script will get the storage account keys for each storage account in the sa_accounts.txt file and export them to a CSV file.

### Requirements ###
# PowerShell 5.1 or higher
# Azure PowerShell module

### Usage ###
# 1. Create a text file named sa_accounts.txt in the same directory as the script
# 2. Populate the sa_accounts.txt file with the storage account names with one per line
# 3. Run the script ./cvps_get_azure_sa_keys.ps1


# Loop through sa_accounts.txt and store each line in array
$sa_accounts = Get-Content -Path sa_accounts.txt

# Loop through each storage account in the array and get the storage account key
foreach ($sa_account in $sa_accounts) {
    
    try {
        $resourceGroupName = Get-AzStorageAccount | Where-Object {$_.StorageAccountName -eq $sa_account} | Select-Object -ExpandProperty ResourceGroupName
        $sa_key = (Get-AzStorageAccountKey -ResourceGroupName $resourcegroupName -Name $sa_account).Value[0]
    }
    catch {
        # capture the error message
        $errorMessage = $_.Exception.Message
        write-host $errorMessage
        write-host "Most likely the storage account name is incorrect or the account does not exist in the Azure subscription. Maybe there is a security or network restriction"
    }


    if ($sa_key) {

        write-host A key was found for $sa_account
        # Create a new object with the storage account name and key
        $sa_object = New-Object -TypeName PSObject -Property @{
            StorageAccountName = $sa_account
            StorageAccountKey = $sa_key
        }
        # Export the object to a CSV file
        $sa_object | Export-Csv -Path sa_keys.csv -Append -NoTypeInformation
        } else {
            write-host No key found for $sa_account
        }

        $sa_key = $null
        
}

    


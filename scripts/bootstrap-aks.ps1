
param(
    [string] $SettingName = "xiaodoli"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
    $gitRootFolder = Split-Path $gitRootFolder -Parent
}
$scriptFolder = Join-Path $gitRootFolder "scripts"
if (-not (Test-Path $scriptFolder)) {
    throw "Invalid script folder '$scriptFolder'"
}
$infraFolder = Join-Path $gitRootFolder "infra"
$settingsFolder = Join-Path $infraFolder "settings"
$bootstrapFolder = Join-Path $infraFolder "bootstrap"

$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "Common.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
$tempFolder = Join-Path $scriptFolder "temp"
if (-not (Test-Path $tempFolder)) {
    New-Item $tempFolder -ItemType Directory -Force | Out-Null
}
$tempFolder = Join-Path $tempFolder $SettingName
if (-not (Test-Path $tempFolder)) {
    New-Item $tempFolder -ItemType Directory -Force | Out-Null
}

InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Setup-AKS"

UsingScope("retrieving settings") {
    $settingYamlFile = Join-Path $settingsFolder "$($SettingName).yaml"
    $settings = Get-Content $settingYamlFile -Raw | ConvertFrom-Yaml
    LogStep -Message "Settings retrieved for '$($settings.global.subscriptionName)'"
}

UsingScope("login") {
    $azAccount = LoginAzureAsUser -SubscriptionName $settings.global.subscriptionName
    $settings.global["subscriptionId"] = $azAccount.id
    $settings.global["tenantId"] = $azAccount.tenantId
    LogStep -Message "Logged in as user '$($azAccount.name)'"
}

UsingScope("Ensure resource group") {
    [array]$existingRgs = az group list --query "[?name=='$($settings.global.resourceGroup.name)']" | ConvertFrom-Json
    if ($null -eq $existingRgs -or $existingRgs.Count -eq 0) {
        $rg = az group create -n $settings.global.resourceGroup.name --location $settings.global.resourceGroup.location | ConvertFrom-Json
        LogStep -Message "Created resource group '$($rg.name)'"
    }
    else {
        $rg = $existingRgs[0]
    }
}

UsingScope("Ensure kv") {
    [array]$existingKvs = az keyvault list --resource-group $rg.name --query "[?name=='$($settings.kv.name)']" | ConvertFrom-Json
    if ($null -eq $existingKvs -or $existingKvs.Count -eq 0) {
        $kv = az keyvault create `
            --resource-group $settings.global.resourceGroup.name `
            --name $settings.kv.name `
            --sku standard `
            --location $settings.global.resourceGroup.location `
            --enabled-for-deployment $true `
            --enabled-for-disk-encryption $true `
            --enabled-for-template-deployment $true | ConvertFrom-Json
        LogStep -Message "Created key vault '$($kv.name)'"
    }
    else {
        $kv = $existingKvs[0]
    }
}

UsingScope("Ensure terraform spn") {
    [array]$terraformSpnsFound = az ad sp list --display-name $settings.terraform.clientAppName | ConvertFrom-Json
    [string]$terraformSpnPwdValue = $null
    [bool]$isSpnNewlyCreated = $false
    $certName = $settings.terraform.clientAppName
    if ($null -eq $terraformSpnsFound -or $terraformSpnsFound.Count -eq 0) {
        LogStep -Message "Ensure terraform app cert is created"
        EnsureCertificateInKeyVault `
            -VaultName $settings.kv.name `
            -CertName $certName `
            -ScriptFolder $ScriptFolder

        LogStep -Message "Create terraform app with cert authentication"
        az ad sp create-for-rbac `
            -n $settings.terraform.clientAppName `
            --role Owner `
            --keyvault $settings.kv.name `
            --cert $certName | Out-Null

        LogStep -Message "Create password for terraform app"
        $terraformSpn = az ad sp list --display-name $settings.terraform.clientAppName | ConvertFrom-Json
        $terraformSpnPwd = Get-OrCreatePasswordInVault `
            -VaultName $settings.kv.name `
            -SecretName $settings.terraform.clientSecret
        $terraformSpnPwdValue = $terraformSpnPwd.value
        az ad sp credential reset --name $terraformSpn.appId --password $terraformSpnPwdValue --append | Out-Null

        LogStep -Message "Granting spn '$($settings.terraform.clientAppName)' 'contributor' role to subscription"
        $existingAssignments = az role assignment list --assignee $terraformSpn.appId --role Owner --scope "/subscriptions/$($azAccount.id)" | ConvertFrom-Json
        if ($existingAssignments.Count -eq 0) {
            az role assignment create --assignee $terraformSpn.appId --role Owner --scope "/subscriptions/$($azAccount.id)" | Out-Null
        }
        else {
            LogInfo -Message "Assignment already exists."
        }

        $isSpnNewlyCreated = $true
    }
    elseif ($terraformSpnsFound.Count -gt 1) {
        throw "duplicated app found with name '$($settings.terraform.clientAppName)'"
    }
    else {
        $terraformSpn = $terraformSpnsFound[0]
    }

    if ($null -eq $terraformSpnPwdValue -or $terraformSpnPwdValue.Length -eq 0) {
        $terraformSpnPwd = Get-OrCreatePasswordInVault -VaultName $settings.kv.name -SecretName $settings.terraform.clientSecret
        $terraformSpnPwdValue = $terraformSpnPwd.value
        az ad sp credential reset --name $terraformSpn.appId --password $terraformSpnPwdValue | Out-Null
    }

    $terraformSpn = az ad sp show --id $terraformSpn.appId | ConvertFrom-Json

    if ($isSpnNewlyCreated) {
        LogStep -Message "Test service principal using password"
        $totalRetries = 0
        $loginIsSuccessful = $false
        while (!$loginIsSuccessful -and $totalRetries -lt 3) {
            try {
                $azAccountFromSpn = LoginAsServicePrincipalUsingPwd `
                    -VaultName $settings.kv.name `
                    -SecretName $settings.terraform.clientSecret `
                    -ServicePrincipalName $settings.terraform.clientAppName `
                    -TenantId $azAccount.tenantId

                if ($null -ne $azAccountFromSpn -and $azAccountFromSpn.id -eq $azAccount.id) {
                    $loginIsSuccessful = $true
                }
            }
            catch {
                $totalRetries++
                Write-Warning "Retry login...wait 10 sec"
                Start-Sleep -Seconds 10
            }
        }
        if (!$loginIsSuccessful) {
            throw "Failed to login"
        }
        else {
            LogInfo -Message "Logged in as '$($azAccountFromSpn.name)'"
        }

        LogInfo -Message "Switch back to user mode"
        LoginAzureAsUser -SubscriptionName $settings.global.subscriptionName | Out-Null
    }

    $settings.terraform["spn"] = @{
        appId    = $terraformSpn.appId
        pwd      = $terraformSpnPwdValue
        objectId = $terraformSpn.objectId
    }
}

UsingScope("Ensure terraform backend") {
    LogStep -Message "Ensure backend storage account '$($settings.terraform.backend.storageAccount)'"
    [array]$storageAccountsFound = az storage account list `
        --resource-group $settings.global.resourceGroup.name `
        --query "[?name=='$($settings.terraform.backend.storageAccount)']" | ConvertFrom-Json
    if ($null -eq $storageAccountsFound -or $storageAccountsFound.Count -eq 0) {
        $tfStorageAccount = az storage account create `
            --name $settings.terraform.backend.storageAccount `
            --resource-group $settings.global.resourceGroup.name `
            --location $settings.global.resourceGroup.location `
            --sku Standard_LRS | ConvertFrom-Json
        LogInfo -Message "storage account '$($tfStorageAccount.name)' is created"
    }
    else {
        $tfStorageAccount = $storageAccountsFound[0]
    }

    LogStep -Message "Get storage key"
    $tfStorageKeys = az storage account keys list -g $settings.global.resourceGroup.name -n $settings.terraform.backend.storageAccount | ConvertFrom-Json
    $tfStorageKey = $tfStorageKeys[0].value

    LogStep -Message "Ensure blob container '$($settings.terraform.backend.containerName)'"
    [array]$blobContainersFound = az storage container list `
        --account-name $tfStorageAccount.name `
        --account-key $tfStorageKey `
        --query "[?name=='$($settings.terraform.backend.containerName)']" | ConvertFrom-Json
    if ($null -eq $blobContainersFound -or $blobContainersFound.Count -eq 0) {
        az storage container create --name $settings.terraform.backend.containerName --account-name $tfStorageAccount.name --account-key $tfStorageKey | Out-Null
    }
    else {
        LogInfo -Message "blob container already created"
    }

    $settings.terraform.backend["accessKey"] = $tfStorageKey
}

UsingScope("Ensure aks server app") {
    $aksServerAppPwdValue = $null
    [array]$aksServerAppsFound = az ad sp list --display-name $settings.aks.serverApp | ConvertFrom-Json

    if ($settings.aks.reuseExistingAadApp) {
        if ($null -eq $aksServerAppsFound -or $aksServerAppsFound.Count -ne 1) {
            throw "Failed to find aks server app '$($settings.aks.serverApp)'"
        }
        else {
            $aksServerApp = $aksServerAppsFound[0]
        }
    }
    else {
        if ($null -eq $aksServerAppsFound -or $aksServerAppsFound.Count -eq 0) {
            $scopes = "/subscriptions/$($azAccount.id)"
            $aksServerApp = az ad sp create-for-rbac `
                --name $settings.aks.serverApp `
                --role="Contributor" `
                --scopes=$scopes | ConvertFrom-Json

            $aksServerAppPwdValue = $aksServerApp.password
            az keyvault secret set --vault-name $settings.kv.name --name $settings.aks.serverSecret --value $aksServerAppPwdValue | Out-Null
        }
        elseif ($aksServerAppsFound.Count -gt 1) {
            throw "Duplicated app found with name '$($settings.aks.serverApp)'"
        }
        else {
            $aksServerApp = $aksServerAppsFound[0]
        }


        LogStep -Message "Update server app access"
        $authJson = @"
    [
        {
          "resourceAccess": [
            {
              "id": "7ab1d382-f21e-4acd-a863-ba3e13f7da61",
              "type": "Role"
            },
            {
              "id": "e1fe6dd8-ba31-4d61-89e7-88639da4683d",
              "type": "Scope"
            },
            {
              "id": "06da0dbc-49e2-44d2-8312-53f166ab848a",
              "type": "Scope"
            }
          ],
          "resourceAppId": "00000003-0000-0000-c000-000000000000"
        },
        {
          "resourceAccess": [
            {
              "id": "311a71cc-e848-46a1-bdf8-97ff7156d8e6",
              "type": "Scope"
            }
          ],
          "resourceAppId": "00000002-0000-0000-c000-000000000000"
        }
      ]
"@
        $spnAuthJsonFile = Join-Path $tempFolder "aks_server_app_auth.json"
        $authJson | Out-File $spnAuthJsonFile

        $totalRetries = 0
        $isSuccessful = $false
        while ($totalRetries -lt 3 -and !$isSuccessful) {
            try {
                az ad app update --id $aksServerApp.appId --required-resource-accesses $spnAuthJsonFile | Out-Null
                az ad app update --id $aksServerApp.appId --reply-urls "http://$($settings.aks.serverApp)" | Out-Null
                $isSuccessful = $true
            }
            catch {
                $isSuccessful = $false
                LogInfo -Message "retry..."
                Start-Sleep -Seconds 10 # wait for app become available
            }
            finally {
                $totalRetries++
            }
        }

        if (!$isSuccessful) {
            throw "Failed to update aks server app '$($aksServerApp.appId)'"
        }
    }
}

UsingScope("Ensure aks client app") {
    [array]$aksServerAppsFound = az ad sp list --display-name $settings.aks.serverApp | ConvertFrom-Json # refresh updated settings
    $aksServerApp = $aksServerAppsFound[0]

    [array]$aksClientSpnsFound = az ad sp list --display-name $settings.aks.clientApp | ConvertFrom-Json
    if ($settings.aks.reuseExistingAadApp) {
        if ($null -eq $aksClientSpnsFound -or $aksClientSpnsFound.Count -ne 1) {
            throw "Failed to find aks client app '$($settings.aks.clientApp)'"
        }
        else {
            $aksClientSpn = $aksClientSpnsFound[0]
        }
    }
    else {
        if ($null -eq $aksClientSpnsFound -or $aksClientSpnsFound.Count -eq 0) {
            $resourceAccess = "[{`"resourceAccess`": [{`"id`": `"318f4279-a6d6-497a-8c69-a793bda0d54f`", `"type`": `"Scope`"}],`"resourceAppId`": `"$($aksServerApp.appId)`"}]"
            $clientAuthJsonFile = Join-Path $tempFolder "aks_client_app_auth.json"
            $resourceAccess | Out-File $clientAuthJsonFile
            $aksClientApp = az ad app create `
                --display-name $settings.aks.clientApp `
                --native-app `
                --reply-urls "http://$($settings.aks.serverApp)" `
                --required-resource-accesses @$clientAuthJsonFile | ConvertFrom-Json

            $aksClientSpn = az ad sp create --id $aksClientApp.appId | ConvertFrom-Json
        }
        elseif ($aksClientSpnsFound.Count -gt 1) {
            throw "Duplicate app found with name '$($settings.aks.clientAppName)'"
        }
        else {
            $aksClientSpn = $aksClientSpnsFound[0]
        }

        az ad app update --id $aksClientSpn.appId --reply-urls "http://$($settings.aks.serverApp)"
    }

    if ($null -eq $aksServerAppPwdValue -or $aksServerAppPwdValue.Length -eq 0) {
        if ($settings.aks.reuseExistingAadApp) {
            $aksServerAppPwd = TryGetSecret -VaultName $settings.kv.name -SecretName $settings.aks.serverSecret
            if ($null -eq $aksServerAppPwd) {
                throw "AKS server app password '$($settings.aks.serverSecret)' is not found in vault '$($settings.kv.name)'"
            }
            else {
                $aksServerAppPwdValue = $aksServerAppPwd.value
            }
        }
        else {
            $aksServerAppPwd = Get-OrCreatePasswordInVault -VaultName $settings.kv.name -SecretName $settings.aks.serverSecret
            $aksServerAppPwdValue = $aksServerAppPwd.value
            az ad sp credential reset --name $aksServerApp.appId --password $aksServerAppPwdValue --append | Out-Null
        }
    }

    $settings.aks["resourceGroup"] = $settings.global.resourceGroup.name
    $settings.aks["location"] = $settings.global.resourceGroup.location
    $settings.aks["server_app_id"] = $aksServerApp.appId
    $settings.aks["server_app_secret"] = $aksServerAppPwdValue
    $settings.aks["client_app_id"] = $aksClientSpn.appId
    $settings.aks["tenant_id"] = $azAccount.tenantId
}

UsingScope("Ensure aad apps permissions") {
    if ($settings.aks.reuseExistingAadApp) {
        LogStep -Message "Skipping grant aks server/client app permission (should already be done)"
    }
    else {
        LogStep -Message "Check aks server app grants"
        az ad app permission admin-consent --id $aksServerApp.appId

        LogStep -Message "Check aks client app grants"
        az ad app permission admin-consent --id $aksClientSpn.appId
    }
}

UsingScope("Ensure SSH key for AKS") {
    $nodeSshKeyFile = Join-Path $tempFolder $settings.aks.ssh.privateKey
    $nodeSshPubFile = $nodeSshKeyFile + ".pub"
    if (Test-Path $nodeSshKeyFile) {
        Remove-Item $nodeSshKeyFile
    }
    if (Test-Path $nodeSshPubFile) {
        Remove-Item $nodeSshPubFile
    }

    $nodeSshKeyPwd = Get-OrCreatePasswordInVault -VaultName $settings.kv.name -SecretName $settings.aks.ssh.privateKeyPwd
    $nodeSshKeySecret = TryGetSecret -VaultName $settings.kv.name -SecretName $settings.aks.ssh.privateKey
    $nodeSshPubSecret = TryGetSecret -VaultName $settings.kv.name -SecretName $settings.aks.ssh.publicKey
    if ($null -eq $nodeSshKeySecret -or $null -eq $nodeSshPubSecret) {
        ssh-keygen -f $nodeSshKeyFile -P $nodeSshKeyPwd.value
        $privateKeyString = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($nodeSshKeyFile))
        az keyvault secret set --vault-name $settings.kv.name --name $settings.aks.ssh.privateKey --value $privateKeyString | Out-Null
        $publicKeyString = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($nodeSshPubFile))
        az keyvault secret set --vault-name $settings.kv.name --name $settings.aks.ssh.publicKey --value $publicKeyString | Out-Null

        $nodeSshPubSecret = az keyvault secret show --vault-name $settings.kv.name --name $settings.aks.ssh.publicKey | ConvertFrom-Json
    }

    $sshPubKeyData = ([string][System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($nodeSshPubSecret.value))).Trim().Replace("\", "\\")
    $settings.aks["nodePublicSshKey"] = $sshPubKeyData
}

UsingScope("Set deployment key") {
    LogStep -Message "Set deployment key to kv"
    $idQuery = "https://$($settings.kv.name).vault.azure.net/secrets/$($settings.gitRepo.deployPublicKey)"
    [array]$deployPubKeyFound = az keyvault secret list `
        --vault-name $settings.kv.name `
        --query "[?starts_with(id, '$idQuery')]" | ConvertFrom-Json

    $idQuery = "https://$($settings.kv.name).vault.azure.net/secrets/$($settings.gitRepo.deployPrivateKey)"
    [array]$deployPrivateKeyFound = az keyvault secret list `
        --vault-name $settings.kv.name `
        --query "[?starts_with(id, '$idQuery')]" | ConvertFrom-Json

    $deploySshKeyFile = Join-Path $tempFolder "flux-deploy-key"
    if (Test-Path $deploySshKeyFile) {
        Remove-Item $deploySshKeyFile -Force
    }
    $sshPubKeyFile = "$($deploySshKeyFile).pub"
    if (Test-Path $sshPubKeyFile) {
        Remove-Item $sshPubKeyFile -Force
    }

    if ($null -eq $deployPrivateKeyFound -or $null -eq $deployPubKeyFound -or $deployPrivateKeyFound.Count -eq 0 -or $deployPubKeyFound.Count -eq 0) {
        ssh-keygen -b 4096 -t rsa -f $deploySshKeyFile
        az keyvault secret set --vault-name $settings.kv.name --name $settings.gitRepo.deployPrivateKey --file $deploySshKeyFile | Out-Null
        az keyvault secret set --vault-name $settings.kv.name --name $settings.gitRepo.deployPublicKey --file $sshPubKeyFile | Out-Null
    }
    else {
        az keyvault secret download --vault-name $settings.kv.name --name $settings.gitRepo.deployPrivateKey -f $deploySshKeyFile
        az keyvault secret download --vault-name $settings.kv.name --name $settings.gitRepo.deployPublicKey -f $sshPubKeyFile
    }

    $settings.gitRepo["deployPrivateKeyFile"] = TranslateToLinuxFilePath -FilePath $deploySshKeyFile
    $settings.gitRepo["repo"] = "git@github.com:$($settings.gitRepo.teamOrUser)/$($settings.gitRepo.name).git"

    LogStep -Message "Add ssh public key to 'https://github.com/$($settings.gitRepo.teamOrUser)/$($settings.gitRepo.name)/settings/keys'"
    $pubDeployKeyData = (Get-Content $sshPubKeyFile -Encoding Ascii)
    $pubDeployKeyData = $pubDeployKeyData.Trim().Replace("\", "\\")
    Write-Host $pubDeployKeyData
}

UsingScope("Setup AKS users/groups") {
    $owners = ""
    $contributors = ""
    $readers = ""

    LogStep -Message "Populating users..."
    if ($null -ne $settings.aks.owners -and $settings.aks.owners.Count -gt 0) {
        $settings.aks.owners | ForEach-Object {
            $username = $_.name
            [array]$usersFound = az ad user list --upn $username | ConvertFrom-Json
            if ($null -ne $usersFound -and $usersFound.Count -eq 1) {
                if ($owners.Length -gt 0) {
                    $owners += ","
                }
                $owners += $usersFound[0].objectId
            }
            else {
                Write-Warning "No user found: '$username'"
            }
        }
    }

    LogStep -Message "Populating contributors..."
    if ($null -ne $settings.aks.contributors -and $settings.aks.contributors.Count -gt 0) {
        $settings.aks.contributors | ForEach-Object {
            $groupName = $_.name
            [array]$groupsFound = az ad group list --display-name $groupName | ConvertFrom-Json
            if ($null -ne $groupsFound -and $groupsFound.Count -eq 1) {
                if ($contributors.Length -gt 0) {
                    $contributors += ","
                }
                $contributors += $groupsFound[0].objectId
            }
            else {
                Write-Warning "No group found: '$groupName'"
            }
        }
    }

    LogStep -Message "Populating readers..."
    if ($null -ne $settings.aks.readers -and $settings.aks.readers.Count -gt 0) {
        $settings.aks.readers | ForEach-Object {
            $groupName = $_.name
            [array]$groupsFound = az ad group list --display-name $groupName | ConvertFrom-Json
            if ($null -ne $groupsFound -and $groupsFound.Count -eq 1) {
                if ($readers.Length -gt 0) {
                    $readers += ","
                }
                $readers += $groupsFound[0].objectId
            }
            else {
                Write-Warning "No group found: '$groupName'"
            }
        }
    }

    $settings.aks["roleAssignments"] = @{
        ownerObjectIds       = $owners
        contributorObjectIds = $contributors
        readerObjectIds      = $readers
    }
}

UsingScope("Setup cosmosdb") {
    if ($null -ne $settings["cosmosdb"]) {
        LogInfo -Message "Collecting collection settings..."
        $collectionSettings = ""
        $settings.cosmosdb.collections | ForEach-Object {
            LogStep -Message "Collection: $($_.name)"
            $partitionKey = if ($null -ne $_["partition"]) { $_["partition"] } else { "/id" }
            $throughput = if ($null -ne $_["throughput"]) { [int]$_["throughput"] } else { 400 }
            $collectionSetting = "$($_.name),$($partitionKey),$($throughput)"
            if ($collectionSettings.Length -gt 0) {
                $collectionSettings += ";"
            }
            $collectionSettings += $collectionSetting
        }
        $settings.cosmosdb["collectionSettings"] = $collectionSettings
    }
    else {
        LogInfo -Message "Skip setting up cosmosdb"
    }
}

UsingScope("Setup terraform variables") {

    LogStep -Message "Apply terraform variables binding..."
    $tfVarFile = Join-Path $bootstrapFolder "terraform.tfvars"
    $tfVarContent = Get-Content $tfVarFile -Raw
    $tfVarContent = Set-YamlValues -ValueTemplate $tfVarContent -Settings $settings

    $backendVarFle = Join-Path $bootstrapFolder "backend.tfvars"
    $backendVarContent = Get-Content $backendVarFle -Raw
    $backendVarContent = Set-YamlValues -ValueTemplate $backendVarContent -Settings $settings

    $terraformOutputFolder = Join-Path $tempFolder "terraform"
    if (Test-Path $terraformOutputFolder) {
        # keep terraform.tfstate, kubeconfig, otherwise it's going to re-create cluster or trying to connect to localhost
        $terraformTempFolder = Join-Path $terraformOutputFolder ".terraform"
        if (Test-Path $terraformTempFolder) {
            Remove-Item $terraformTempFolder -Recurse -Force
        }
    }
    else {
        New-Item $terraformOutputFolder -ItemType Directory -Force | Out-Null
    }

    LogStep -Message "Write terraform output to '$terraformOutputFolder'"
    $tfVarContent | Out-File (Join-Path $terraformOutputFolder "terraform.tfvars") -Encoding ascii -Force
    $backendVarContent | Out-File (Join-Path $terraformOutputFolder "backend.tfvars") -Encoding ascii -Force
    Copy-Item (Join-Path $bootstrapFolder "main.tf") -Destination (Join-Path $terraformOutputFolder "main.tf") -Force
    Copy-Item (Join-Path $bootstrapFolder "variables.tf") -Destination (Join-Path $terraformOutputFolder "variables.tf") -Force
    Set-Location $terraformOutputFolder
    $terraformInitFolder = Join-Path $terraformOutputFolder ".terraform"
    if (Test-Path $terraformInitFolder) {
        Remove-Item $terraformInitFolder -Recurse -Force
    }

    $terraformShellScriptFile = Join-Path $scriptFolder "run-terraform.sh"
    $scriptContent = Get-Content $terraformShellScriptFile -Raw
    $scriptContent = Set-YamlValues -ValueTemplate $scriptContent -Settings $settings
    $terraformShellFile = Join-Path $terraformOutputFolder "run-terraform.sh"
    $scriptContent | Out-File $terraformShellFile -Encoding ascii -Force | Out-Null
    Invoke-Expression "chmod +x `"$terraformShellFile`""
}

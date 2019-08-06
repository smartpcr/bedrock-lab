
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

$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
$tempFolder = Join-Path $scriptFolder "temp"
if (-not (Test-Path $tempFolder)) {
    New-Item $tempFolder -ItemType Directory -Force | Out-Null
}

InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Setup-AKS"

UsingScope("retrieving settings") {
    $infraFolder = Join-Path $gitRootFolder "infra"
    $bootstrapFolder = Join-Path $infraFolder "bootstrap"
    $settingYamlFile = Join-Path $bootstrapFolder "setting.yaml"
    $settings = Get-Content $settingYamlFile -Raw | ConvertFrom-Yaml
}

UsingScope("login") {
    $azAccount = az account show | ConvertFrom-Json
    if ($null -eq $azAccount -or $azAccount.name -ne $settings.global.subscriptionName) {
        az login
        az account set -s $settings.global.subscriptionName
        $azAccount = az account show | ConvertFrom-Json
    }

    $settings.global["subscriptionId"] = $azAccount.id
    $settings.global["tenantId"] = $azAccount.tenantId
}

UsingScope("Ensure resource group") {
    [array]$existingRgs = az group list --query "[?name=='$($settings.global.resourceGroup.name)']" | ConvertFrom-Json
    if ($null -eq $existingRgs -or $existingRgs.Count -eq 0) {
        $rg = az group create -n $settings.global.resourceGroup.name --location $settings.global.resourceGroup.location | ConvertFrom-Json
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
    }
    else {
        $kv = $existingKvs[0]
    }
}

UsingScope("Ensure spn") {
    LogStep -Message "Ensure Terraform SPN"

    [array]$terraformSpnsFound = az ad sp list --display-name $settings.terraform.clientAppName | ConvertFrom-Json
    if ($null -eq $terraformSpnsFound -or $terraformSpnsFound.Count -eq 0) {
        $scopes = "/subscriptions/$($azAccount.id)"
        $terraformSpn = az ad sp create-for-rbac `
            --name $settings.terraform.clientAppName `
            --role="Owner" `
            --scopes=$scopes | ConvertFrom-Json

        az keyvault secret set --vault-name $settings.kv.name --name $settings.terraform.clientSecret --value $terraformSpn.password | Out-Null
    }
    elseif ($terraformSpnsFound.Count -gt 1) {
        throw "duplicated app found with name '$($settings.terraform.clientAppName)'"
    }
    else {
        $terraformSpn = $terraformSpnsFound[0]
    }

    $terraformSpnPwd = az keyvault secret show --vault-name $settings.kv.name --name $settings.terraform.clientSecret | ConvertFrom-Json

    $settings.terraform["spn"] = @{
        appId = $terraformSpn.appId
        pwd = $terraformSpnPwd.value
    }

    LogStep -Message "Ensure AKS Server App"
    [array]$aksServerAppsFound = az ad sp list --display-name $settings.aks.serverApp | ConvertFrom-Json
    if ($null -eq $aksServerAppsFound -or $aksServerAppsFound.Count -eq 0) {
        $scopes = "/subscriptions/$($azAccount.id)"
        $aksServerApp = az ad sp create-for-rbac `
            --name $settings.aks.serverApp `
            --role="Contributor" `
            --scopes=$scopes | ConvertFrom-Json

        az keyvault secret set --vault-name $settings.kv.name --name $settings.aks.serverSecret --value $aksServerApp.password | Out-Null
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
    az ad app update --id $aksServerApp.appId --required-resource-accesses $spnAuthJsonFile | Out-Null
    az ad app update --id $aksServerApp.appId --reply-urls "http://$($settings.aks.serverApp)" | Out-Null

    LogStep -Message "Ensure AKS Client App"
    [array]$aksServerAppsFound = az ad sp list --display-name $settings.aks.serverApp | ConvertFrom-Json # refresh updated settings
    $aksServerApp = $aksServerAppsFound[0]
    [array]$aksClientAppsFound = az ad app list --display-name $settings.aks.clientApp | ConvertFrom-Json
    if ($null -eq $aksClientAppsFound -or $aksClientAppsFound.Count -eq 0) {
        $resourceAccess = "[{`"resourceAccess`": [{`"id`": `"318f4279-a6d6-497a-8c69-a793bda0d54f`", `"type`": `"Scope`"}],`"resourceAppId`": `"$($aksServerApp.appId)`"}]"
        $clientAuthJsonFile = Join-Path $tempFolder "aks_client_app_auth.json"
        $resourceAccess | Out-File $clientAuthJsonFile
        $aksClientApp = az ad app create `
            --display-name $settings.aks.clientApp `
            --native-app `
            --reply-urls "http://$($settings.aks.serverApp)" `
            --required-resource-accesses @$clientAuthJsonFile | ConvertFrom-Json
    }
    elseif ($aksClientAppsFound.Count -gt 1) {
        throw "Duplicate app found with name '$($settings.aks.clientAppName)'"
    }
    else {
        $aksClientApp = $aksClientAppsFound[0]
    }

    az ad app update --id $aksClientApp.appId --reply-urls "http://$($settings.aks.serverApp)"
    $aksServerAppPwd = az keyvault secret show --vault-name $settings.kv.name --name $settings.aks.serverSecret | ConvertFrom-Json

    $settings.aks["resourceGroup"] = $settings.global.resourceGroup.name
    $settings.aks["location"] = $settings.global.resourceGroup.location
    $settings.aks["server_app_id"] = $aksServerApp.appId
    $settings.aks["server_app_secret"] = $aksServerAppPwd.value
    $settings.aks["client_app_id"] = $aksClientApp.appId
    $settings.aks["tenant_id"] = $azAccount.tenantId
}


UsingScope("Ensure SSH key for AKS") {
    $sshKeyFile = Join-Path $tempFolder $settings.aks.ssh.privateKey
    $sshPubFile = $sshKeyFile + ".pub"
    if (Test-Path $sshKeyFile) {
        Remove-Item $sshKeyFile
    }
    if (Test-Path $sshPubFile) {
        Remove-Item $sshPubFile
    }

    $sshKeyPwd = Get-OrCreatePasswordInVault -VaultName $settings.kv.name -SecretName $settings.aks.ssh.privateKeyPwd
    $sshPrivateKeysFound = az keyvault secret list --vault-name $settings.kv.name --query "[?id=='https://$($settings.kv.name).vault.azure.net/secrets/$($settings.aks.ssh.privateKey)']" | ConvertFrom-Json
    if ($null -eq $sshPrivateKeysFound -or $sshPrivateKeysFound.Count -eq 0) {
        ssh-keygen -f $sshKeyFile -P $sshKeyPwd.value
        $privateKeyString = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($sshKeyFile))
        az keyvault secret set --vault-name $settings.kv.name --name $settings.aks.ssh.privateKey --value $privateKeyString | Out-Null
        $publicKeyString = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($sshPubFile))
        az keyvault secret set --vault-name $settings.kv.name --name $settings.aks.ssh.publicKey --value $publicKeyString | Out-Null
    }

    $sshPubKey = az keyvault secret show --vault-name $settings.kv.name --name $settings.aks.ssh.publicKey | ConvertFrom-Json
    $sshPubKeyData = ([string][System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($sshPubKey.value))).Trim().Replace("\", "\\")
    $settings.aks["nodePublicSshKey"] = $sshPubKeyData
}



UsingScope("Set deployment key") {
    LogStep -Message "Set deployment key to kv"
    [array]$deployPubKeyFound = az keyvault secret list `
        --vault-name $settings.kv.name `
        --query "[?id=='https://$($settings.kv.name).vault.azure.net/secrets/$($settings.gitRepo.deployPublicKey)']" | ConvertFrom-Json
    [array]$deployPrivateKeyFound = az keyvault secret list `
        --vault-name $settings.kv.name `
        --query "[?id=='https://$($settings.kv.name).vault.azure.net/secrets/$($settings.gitRepo.deployPrivateKey)']" | ConvertFrom-Json
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
        az keyvault secret download --vault-name $settings.kv.name --name $settings.gitRepo.deployPrivateKey -e base64 -f $deploySshKeyFile
        az keyvault secret download --vault-name $settings.kv.name --name $settings.gitRepo.deployPublicKey -e base64 -f $sshPubKeyFile
    }

    $settings.gitRepo["deployPrivateKeyFile"] = $deploySshKeyFile
    $settings.gitRepo["repo"] = "git@github.com:$($settings.gitRepo.teamOrUser)/$($settings.gitRepo.name).git"
    $settings.gitRepo["gitops_ssh_key"] = $sshPubKeyFile
}


UsingScope("Setup terraform variables") {

    LogStep -Message "Apply terraform variables binding..."
    $tfVarFile = Join-Path $bootstrapFolder "terraform.tfvars"
    $tfVarContent = Get-Content $tfVarFile -Raw
    $tfVarContent = Set-YamlValues -ValueTemplate $tfVarContent -Settings $settings
    $terraformOutputFolder = Join-Path $tempFolder "terraform"
    if (-not (Test-Path $terraformOutputFolder)) {
        New-Item $terraformOutputFolder -ItemType Directory -Force | Out-Null
    }

    LogStep -Message "Write terraform output to '$terraformOutputFolder'"
    $tfVarContent | Out-File (Join-Path $terraformOutputFolder "terraform.tfvars") -Encoding ascii -Force
    Copy-Item (Join-Path $bootstrapFolder "main.tf") -Destination (Join-Path $terraformOutputFolder "main.tf") -Force
    Copy-Item (Join-Path $bootstrapFolder "variables.tf") -Destination (Join-Path $terraformOutputFolder "variables.tf") -Force
    Set-Location $terraformOutputFolder
    terraform init

    LogStep -Message "Setup terraform env vars"
    $env:ARM_SUBSCRIPTION_ID = $azAccount.id
    $env:ARM_TENANT_ID = $azAccount.tenantId
    $env:ARM_CLIENT_SECRET = $terraformSpnPwd.value
    $env:ARM_CLIENT_ID = $terraformSpn.appId
    terraform plan -var-file="terraform.tfvars"

    LogStep -Message "Apply terraform manifest"
    terraform apply -var-file="terraform.tfvars"
}


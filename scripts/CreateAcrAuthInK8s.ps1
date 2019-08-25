
param(
    [string]$SettingName = "sace",
    [array]$AdditionK8sNamespaces = @("ingress-nginx", "monitoring", "dns", "flux")
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
$moduleFolder = Join-Path $scriptFolder "modules"

Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "Common.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force

InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Setup acr-auth in k8s"

UsingScope("retrieving settings") {
    $settingYamlFile = Join-Path $settingsFolder "$($SettingName).yaml"
    $settings = Get-Content $settingYamlFile -Raw | ConvertFrom-Yaml
    LogStep -Message "Settings retrieved for '$($settings.global.subscriptionName)/$($SettingName)'"
}
$VaultName = $settings.kv.name
$AcrName = $settings.acr.name
$Email = $settings.acr.email

UsingScope("login") {
    $azAccount = LoginAzureAsUser -SubscriptionName $settings.global.subscriptionName
    $settings.global["subscriptionId"] = $azAccount.id
    $settings.global["tenantId"] = $azAccount.tenantId
    LogStep -Message "Logged in as user '$($azAccount.name)'"

    LogStep -Message "Connect to aks"
    az aks get-credentials -g $settings.global.resourceGroup.name -n $settings.aks.clusterName --overwrite-existing --admin
}


$acrCredential = az acr credential show -n $AcrName | ConvertFrom-Json
[array]$acrPwdSecrets = az keyvault secret list --vault-name $VaultName --query "[?id=='https://$($VaultName).vault.azure.net/secrets/$($AcrName)-pwd']" | ConvertFrom-Json
$NeedUpdate = $true
if ($null -ne $acrPwdSecrets -and $acrPwdSecrets.Count -eq 1) {
    $acrPwdSecret = az keyvault secret show --vault-name $VaultName --name "$($AcrName)-pwd" | ConvertFrom-Json
    if ($acrPwdSecret.value -eq $acrCredential.passwords[0].value) {
        $NeedUpdate = $false
    }
}
if ($NeedUpdate) {
    az keyvault secret set --vault-name $VaultName --name "$($AcrName)-pwd" --value $acrCredential.passwords[0].value | Out-Null
}

kubectl create secret docker-registry acr-auth `
    --docker-server "$AcrName.azurecr.io" `
    --docker-username $AcrName `
    --docker-password $acrCredential.passwords[0].value `
    --docker-email $Email -n default

$AdditionK8sNamespaces | ForEach-Object {
    kubectl create secret docker-registry acr-auth `
        --docker-server "$AcrName.azurecr.io" `
        --docker-username $AcrName `
        --docker-password $acrCredential.passwords[0].value `
        --docker-email $Email -n $_
}
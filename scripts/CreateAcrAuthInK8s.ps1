
param(
    [string]$VaultName = "xiaodoli-bedrock-kv",
    [string]$AcrName = "xiaodolibedrockacr",
    [string]$ResourceGroupName = "xiaodoli-bedrock-lab",
    [string]$Email = "xiaodoli@microsoft.com",
    [array]$AdditionK8sNamespaces=@("nginx", "monitoring")
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$acrCredential = az acr credential show -n $AcrName | ConvertFrom-Json
[array]$acrPwdSecret = az keyvault secret list --vault-name $VaultName --query "[?id=='https://$($VaultName).vault.azure.net/secrets/$($AcrName)-pwd']" | ConvertFrom-Json
$NeedUpdate = $true
if ($null -ne $acrPwdSecret -and $acrPwdSecret.Count -eq 1) {
    if ($acrPwdSecret[0].value -eq $acrCredential.passwords[0].value) {
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
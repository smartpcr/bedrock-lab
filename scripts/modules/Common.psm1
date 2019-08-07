
function LoginAzureAsUser {
    param (
        [string] $SubscriptionName
    )

    $azAccount = az account show | ConvertFrom-Json
    if ($null -eq $azAccount -or $azAccount.name -ine $SubscriptionName) {
        az login | Out-Null
        az account set --subscription $SubscriptionName | Out-Null
    }
    elseif ($azAccount.user.type -eq "servicePrincipal") {
        az login | Out-Null
        az account set --subscription $SubscriptionName | Out-Null
    }

    $currentAccount = az account show | ConvertFrom-Json
    return $currentAccount
}

function LoginAsServicePrincipalUsingCert {
    param (
        [string] $VaultName,
        [string] $CertName,
        [string] $ServicePrincipalName,
        [string] $TenantId,
        [string] $ScriptFolder
    )

    $credentialFolder = Join-Path $ScriptFolder "credential"
    if (-not (Test-Path $credentialFolder)) {
        New-Item $credentialFolder -ItemType Directory -Force | Out-Null
    }
    $privateKeyFilePath = Join-Path $credentialFolder "$certName.key"
    if (-not (Test-Path $privateKeyFilePath)) {
        LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
        DownloadCertFromKeyVault -VaultName $vaultName -CertName $certName -ScriptFolder $ScriptFolder
    }

    LogInfo -Message "Login as service principal '$ServicePrincipalName'"
    $azAccountFromSpn = az login --service-principal `
        -u "http://$ServicePrincipalName" `
        -p $privateKeyFilePath `
        --tenant $TenantId | ConvertFrom-Json
    return $azAccountFromSpn
}

function LoginAsServicePrincipalUsingPwd {
    param (
        [string] $VaultName,
        [string] $SecretName,
        [string] $ServicePrincipalName,
        [string] $TenantId
    )

    $clientSecret = az keyvault secret show --vault-name $VaultName --name $SecretName | ConvertFrom-Json
    $azAccountFromSpn = az login --service-principal `
        --username "http://$ServicePrincipalName" `
        --password $clientSecret.value `
        --tenant $TenantId | ConvertFrom-Json
    return $azAccountFromSpn
}
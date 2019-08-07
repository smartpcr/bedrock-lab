
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

function LoginAsServicePrincipal {
    param (
        [string] $EnvName = "dev",
        [string] $SpaceName = "xiaodoli",
        [string] $EnvRootFolder
    )

    $bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -SpaceName $SpaceName -EnvRootFolder $EnvRootFolder
    $azAccount = LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName
    $vaultName = $bootstrapValues.kv.name
    $spnName = $bootstrapValues.global.servicePrincipal
    $certName = $spnName
    $tenantId = $azAccount.tenantId

    $privateKeyFilePath = "$EnvRootFolder/credential/$certName.key"
    if (-not (Test-Path $privateKeyFilePath)) {
        LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
        DownloadCertFromKeyVault -VaultName $vaultName -CertName $certName -EnvRootFolder $EnvRootFolder
    }

    LogInfo -Message "Login as service principal '$spnName'"
    az login --service-principal -u "http://$spnName" -p $privateKeyFilePath --tenant $tenantId | Out-Null
}
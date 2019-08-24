
param(
    [string]$SettingName = "sace"
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
$secretsFolder = Join-Path $settingsFolder "secrets"
$certsYamlFile = Join-Path $secretsFolder "certs.yaml"
$secretsYamlFile = Join-Path $secretsFolder "secrets.yaml"

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
$certsTempFolder = Join-Path $scriptFolder "certs"
if (-not (Test-Path $certsTempFolder)) {
    New-Item $certsTempFolder -ItemType Directory -Force | Out-Null
}
$secretsTempFolder = Join-Path $scriptFolder "secrets"
if (-not (Test-Path $secretsTempFolder)) {
    New-Item $secretsTempFolder -ItemType Directory -Force | Out-Null
}

InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Setup-KeyVault"

UsingScope("retrieving settings") {
    $settingYamlFile = Join-Path $settingsFolder "$($SettingName).yaml"
    $settings = Get-Content $settingYamlFile -Raw | ConvertFrom-Yaml
    LogStep -Message "Settings retrieved for '$($settings.global.subscriptionName)$($SettingName)'"

    $certs = Get-Content $certsYamlFile -Raw | ConvertFrom-Yaml
    LogStep -Message "Total of $($certs.certs.Count) certs found for kv"

    $secrets = Get-Content $secretsYamlFile -Raw | ConvertFrom-Yaml
    LogStep -Message "Total of $($secrets.secrets.Count) secrets found for kv"
}

UsingScope("login") {
    $azAccount = LoginAzureAsUser -SubscriptionName $settings.global.subscriptionName
    $settings.global["subscriptionId"] = $azAccount.id
    $settings.global["tenantId"] = $azAccount.tenantId
    LogStep -Message "Logged in as user '$($azAccount.name)'"
}

UsingScope("Download certs") {
    $SrcVaultName = $certs.backup.vaultName
    if ($settings.global.subscriptionName -ne $certs.backup.subscription) {
        LoginAzureAsUser -SubscriptionName $certs.backup.subscription | Out-Null
    }

    $downloadedCertFiles = New-Object System.Collections.ArrayList
    $totalCerts = $certs.certs.Count
    $certsExported = 0
    $certs.certs | ForEach-Object {
        $certId = [string]$_
        $certName = $certId.Substring($certId.LastIndexOf("/") + 1)
        LogInfo -Message "Downloading cert '$certName'..."
        $certFile = Join-Path $certsTempFolder "$certName.pfx"
        if (Test-Path $certFile) {
            Remove-Item $certFile -Force | Out-Null
        }
        if ($certName.EndsWith("-Managed")) {
            az keyvault secret download --vault-name $SrcVaultName --name $certName -e base64 -f $certFile
        }
        else {
            az keyvault certificate download --file $certFile --name $certName --encoding PEM --vault-name $SrcVaultName
        }

        $downloadedCertFiles.Add(@{
                CertName = $certName
                CertFile = $certFile
            }) | Out-Null

        $certsExported ++
        LogInfo -Message "Exported $certsExported of $totalCerts..."
    }

    $allCertsJsonFile = Join-Path $certsTempFolder "allcerts.json"
    $downloadedCertFiles | ConvertTo-Json -Depth 10 | Out-File $allCertsJsonFile -Encoding UTF8
}

UsingScope("Download secrets") {
    $SrcVaultName = $secrets.backup.vaultName
    if ($settings.global.subscriptionName -ne $secrets.backup.subscription) {
        LoginAzureAsUser -SubscriptionName $secrets.backup.subscription | Out-Null
    }
    $downloadedSecrets = New-Object System.Collections.ArrayList
    $totalSecrets = $secrets.secrets.Count
    $secretsDownloaded = 0
    $secrets.secrets | ForEach-Object {
        $secretName = $_
        LogInfo -Message "Downloading secret '$secretName'..."
        $secret = az keyvault secret show --vault-name $SrcVaultName --name $secretName | ConvertFrom-Json
        $downloadedSecrets.Add(@{
                Name  = $secretName
                Value = $secret.value
            }) | Out-Null

        $secretsDownloaded++
        LogInfo -Message "Downloaded $secretsDownloaded of $totalSecrets..."
    }

    $secretsJsonFile = Join-Path $secretsTempFolder "secrets.json"
    $downloadedSecrets | ConvertTo-Json -Depth 10 | Out-File $secretsJsonFile -Encoding utf8
}

LoginAzureAsUser -SubscriptionName $settings.global.subscriptionName | Out-Null
UsingScope("Import secrets") {
    $TgtVaultName = $settings.kv.name
    $secrets = Get-Content $secretsJsonFile | ConvertFrom-Json
    $totalSecrets = $secrets.Length
    $secretsImported = 0

    $secrets | ForEach-Object {
        $name = $_.Name
        $value = $_.Value
        LogInfo -Message "Importing secret '$name'..."
        $certFound = $downloadedCertFiles | Where-Object { $_.CertName -eq $name }
        if ($null -eq $certFound) {
            $secretExist = IsSecretExists -VaultName $TgtVaultName -SecretName $name
            if ($secretExist -eq $true) {
                az keyvault secret delete --name $name --vault-name $TgtVaultName | Out-Null
            }
            $tempFile = Join-Path $secretsTempFolder $name
            if (Test-Path $tempFile) {
                Remove-Item $tempFile -Force | Out-Null
            }
            # current version of cross-platform powershell generate newline when using Out-File
            [System.IO.File]::WriteAllText($tempFile, $value, [System.Text.Encoding]::ASCII)
            az keyvault secret set --vault-name $TgtVaultName --name $name --file $tempFile --encoding ascii | Out-Null
            $secretsImported++
            # Remove-Item $tempFile -Force | Out-Null
            LogInfo -Message "Imported $secretsImported of $($totalSecrets) secrets"
        }
        else {
            LogInfo -Message "Skipping import secret '$name', since it's managed by cert"
        }
    }
}

UsingScope("Import certs") {
    $TgtVaultName = $settings.kv.name
    $certsImported = 0

    $downloadedCertFiles | ForEach-Object {
        $name = $_.CertName
        $file = $_.CertFile
        LogInfo -Message "Importing cert '$name'..."
        $certAlreadyExist = IsCertExists -VaultName $TgtVaultName -CertName $name
        if ($certAlreadyExist -eq $true) {
            az keyvault certificate delete --vault-name $TgtVaultName --name $name | Out-Null
        }
        $certSecretExist = IsSecretExists -VaultName $TgtVaultName -SecretName $name
        if ($certSecretExist -eq $true) {
            az keyvault secret delete --vault-name $TgtVaultName --name $name | Out-Null
        }
        az keyvault certificate import --file $file --name $name --vault-name $TgtVaultName | Out-Null
        $certsImported++
        LogInfo -Message "Imported $certsImported of $($downloadedCertFiles.Count) certs"
        Remove-Item $file -Force | Out-Null
    }
}

UsingScope("Create k8s certs") {
    $k8sCertCreated = 0

}

LogInfo "Done!"
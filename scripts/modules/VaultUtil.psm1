function Get-OrCreatePasswordInVault {
    param(
        [string] $VaultName,
        [string] $SecretName
    )

    $idQuery = "https://$($VaultName).vault.azure.net/secrets/$($SecretName)"
    [array]$secretsFound = az keyvault secret list `
        --vault-name $VaultName `
        --query "[?starts_with(id, '$idQuery')]" | ConvertFrom-Json

    $secretIsFound = $false
    if ($null -eq $secretsFound -or $secretsFound.Count -eq 0) {
        $secretsFound = $false
    }
    else {
        $secretIsFound = $true
    }

    if (!$secretIsFound) {
        LogInfo -Message "creating new secret '$SecretName'"
        $password = [System.Guid]::NewGuid().ToString()
        az keyvault secret set --vault-name $VaultName --name $SecretName --value $password | Out-Null
        $res = az keyvault secret show --vault-name $VaultName --name $SecretName | ConvertFrom-Json
        return $res
    }

    $res = az keyvault secret show --vault-name $VaultName --name $SecretName | ConvertFrom-Json
    if ($res) {
        return $res
    }
}

function EnsureCertificateInKeyVault {
    param(
        [string] $VaultName,
        [string] $CertName,
        [string] $ScriptFolder
    )

    $existingCert = az keyvault certificate list --vault-name $VaultName --query "[?id=='https://$VaultName.vault.azure.net/certificates/$CertName']" | ConvertFrom-Json
    if ($existingCert) {
        LogInfo -Message "Certificate '$CertName' already exists in vault '$VaultName'"
    }
    else {
        $credentialFolder = Join-Path $ScriptFolder "credential"
        New-Item -Path $credentialFolder -ItemType Directory -Force | Out-Null
        $defaultPolicyFile = Join-Path $credentialFolder "default_policy.json"
        az keyvault certificate get-default-policy -o json | Out-File $defaultPolicyFile -Encoding utf8
        az keyvault certificate create -n $CertName --vault-name $vaultName -p @$defaultPolicyFile | Out-Null
    }
}

function DownloadCertFromKeyVault {
    param(
        [string]$VaultName,
        [string]$CertName,
        [string]$ScriptFolder
    )

    $credentialFolder = Join-Path $ScriptFolder "credential"
    if (-not (Test-Path $credentialFolder)) {
        New-Item $credentialFolder -ItemType Directory -Force | Out-Null
    }
    $pfxCertFile = Join-Path $credentialFolder "$CertName.pfx"
    $pemCertFile = Join-Path $credentialFolder "$CertName.pem"
    $keyCertFile = Join-Path $credentialFolder "$CertName.key"
    if (Test-Path $pfxCertFile) {
        Remove-Item $pfxCertFile
    }
    if (Test-Path $pemCertFile) {
        Remove-Item $pemCertFile
    }
    if (Test-Path $keyCertFile) {
        Remove-Item $keyCertFile
    }
    az keyvault secret download --vault-name $settings.kv.name -n $CertName -e base64 -f $pfxCertFile
    openssl pkcs12 -in $pfxCertFile -clcerts -nodes -out $keyCertFile -passin pass:
    openssl rsa -in $keyCertFile -out $pemCertFile
}

function TryGetSecret() {
    param(
        [string]$VaultName,
        [string]$SecretName
    )

    $idQuery = "https://$($VaultName).vault.azure.net/secrets/$($SecretName)"
    [array]$secretsFound = az keyvault secret list `
        --vault-name $VaultName `
        --query "[?starts_with(id, '$idQuery')]" | ConvertFrom-Json
    $secretIsFound = $false
    if ($null -eq $secretsFound -or $secretsFound.Count -eq 0) {
        $secretsFound = $false
    }
    else {
        $secretIsFound = $true
    }

    if ($secretIsFound) {
        $secret = az keyvault secret show --vault-name $VaultName --name $SecretName | ConvertFrom-Json
        return $secret
    }

    return $null
}

function IsCertExists() {
    param(
        [string]$VaultName,
        [string]$CertName
    )

    [array]$existingCerts = az keyvault certificate list --vault-name $VaultName --query "[?name=='$CertName']" | ConvertFrom-Json
    return $null -ne $existingCerts -and $existingCerts.Count -gt 0
}

function IsSecretExists() {
    param(
        [string]$VaultName,
        [string]$SecretName
    )

    [array]$existingSecrets = az keyvault secret list --vault-name $VaultName --query "[?name=='$SecretName']" | ConvertFrom-Json
    return $null -ne $existingSecrets -and $existingSecrets.Count -gt 0
}

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

function Initialize-BouncyCastleSupport {
    $tempPath = $env:TEMP
    if ($null -eq $tempPath) {
        $tempPath = "/tmp"
    }

    $bouncyCastleDllPath = Join-Path $tempPath "BouncyCastle.Crypto.dll"

    if (-not (Test-Path $bouncyCastleDllPath)) {
        Invoke-WebRequest `
            -Uri "https://avalanchebuildsupport.blob.core.windows.net/files/BouncyCastle.Crypto.dll" `
            -OutFile $bouncyCastleDllPath
    }

    [System.Reflection.Assembly]::LoadFile($bouncyCastleDllPath) | Out-Null
}

function CreateK8sSecretFromCert() {
    param(
        [string]$CertName,
        [string]$VaultName,
        [string]$K8sSecretName,
        [string]$CertDataKey = "tls.cert",
        [string]$KeyDataKey = "tls.key",
        [array]$ExtraK8sNamespaces = @("monitoring","logging")
    )

    Initialize-BouncyCastleSupport

    $certificate = $null
    $secret = az keyvault secret show --vault-name $VaultName --name $CertName | ConvertFrom-Json
    if ([bool]($secret.Attributes.PSobject.Properties.name -match "ContentType")) {
        if ($secret.Attributes.ContentType -eq "application/x-pkcs12") {
            $certificate = @{
                data     = $secret.value
                password = ""
            }
        }
    }

    if ($null -eq $certificate) {
        $certificateBytes = [System.Convert]::FromBase64String($secret.value)
        $jsonCertificate = [System.Text.Encoding]::UTF8.GetString($certificateBytes) | ConvertFrom-Json
        $certificate = @{
            data     = $jsonCertificate.data
            password = $jsonCertificate.password
        }
    }

    $pfxFile = New-TemporaryFile
    $crtFile = $pfxFile.FullName + ".crt"
    $keyFile = $pfxFile.FullName + ".key"
    try {
        $data = [System.Convert]::FromBase64String($certificate.data)
        $certObject = New-Object 'System.Security.Cryptography.X509Certificates.X509Certificate2' ($data, $certificate.password, "Exportable")
        $certText = ""
        $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
        $chain.ChainPolicy.RevocationMode = "NoCheck"
        [void]$chain.Build($certObject)
        $chain.ChainElements | ForEach-Object {
            $certText += "-----BEGIN CERTIFICATE-----`n" + [Convert]::ToBase64String($_.Certificate.Export('Cert'), 'InsertLineBreaks') + "`n-----END CERTIFICATE-----`n"
        }
        Set-Content -LiteralPath $crtFile -Value $certText

        $keyPair = [Org.BouncyCastle.Security.DotNetUtilities]::GetRsaKeyPair($certObject.PrivateKey)
        $streamWriter = [System.IO.StreamWriter]$keyFile
        try {
            $pemWriter = New-Object 'Org.BouncyCastle.OpenSsl.PemWriter' ($streamWriter)
            $pemWriter.WriteObject($keyPair.Private)
        }
        finally {
            $streamWriter.Dispose()
        }

        LogInfo -Message "Setup k8s secret for '$K8sSecretName' as cert"
        $certContent = Get-Content -LiteralPath $crtFile -Raw
        $keyContent = Get-Content -LiteralPath $keyFile -Raw
        $genevaSecretYaml = @"
---
apiVersion: v1
kind: Secret
metadata:
  name: $($K8sSecretName)
data:
  $($CertDataKey): $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($certContent)))
  $($KeyDataKey): $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($keyContent)))
type: Opaque
"@
        $genevaSecretYaml | kubectl apply --namespace default -f -
        if ($null -ne $ExtraK8sNamespaces -and $ExtraK8sNamespaces.Count -gt 0) {
            $ExtraK8sNamespaces | ForEach-Object {
                $k8sns = $_
                $genevaSecretYaml | kubectl apply --namespace $k8sns -f -
            }
        }

    }
    finally {
        Remove-Item -LiteralPath $crtFile -Force -ErrorAction Ignore
        Remove-Item -LiteralPath $keyFile -Force -ErrorAction Ignore
        Remove-Item -LiteralPath $pfxFile -Force -ErrorAction Ignore
    }
}

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

function TranslateToLinuxFilePath() {
    param(
        [string]$FilePath = "C:/work/github/container/bedrock-lab/scripts/temp/aamva/flux-deploy-key"
    )

    $isWindowsOs = ($PSVersionTable.PSVersion.Major -lt 6) -or ($PSVersionTable.Platform -eq "Win32NT")
    if ($isWindowsOs) {
        # this is for running inside WSL
        $FilePath = $FilePath.Replace("\", "/")
        $driveLetter = Split-Path $FilePath -Qualifier
        $driveLetter = $driveLetter.TrimEnd(':')
        return $FilePath.Replace("$($driveLetter):", "/mnt/$($driveLetter.ToLower())")
    }

    return $FilePath
}

function StipSpaces() {
    param(
        [ValidateSet("key", "pub")]
        [string]$FileType,
        [string]$FilePath
    )

    $fileContent = Get-Content $FilePath -Raw
    $fileContent = $fileContent.Replace("`r", "")
    if ($FileType -eq "key") {
        # 3 parts
        $parts = $fileContent.Split("`n")
        if ($parts.Count -gt 3) {
            $builder = New-Object System.Text.StringBuilder
            $lineNumber = 0
            $parts | ForEach-Object {
                if ($lineNumber -eq 0) {
                    $builder.AppendLine($_) | Out-Null
                }
                elseif ($lineNumber -eq $parts.Count - 1) {
                    $builder.Append("`n$_") | Out-Null
                }
                else {
                    $builder.Append($_) | Out-Null
                }
                $lineNumber++
            }
            $fileContent = $builder.ToString()
        }
    }

    $fileContent | Out-File $FilePath -Encoding ascii -Force
}
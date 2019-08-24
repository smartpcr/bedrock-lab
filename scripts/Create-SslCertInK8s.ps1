param(
    [string]$SettingName = "xiaodoli",
    [string]$BackupVaultName = "xiaodong-kv"
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

InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Setup ssl cert and dns config"

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


UsingScope("Ensure terraform spn") {
    [array]$terraformSpnsFound = az ad sp list --display-name $settings.terraform.clientAppName | ConvertFrom-Json
    [string]$terraformSpnPwdValue = $null

    if ($null -eq $terraformSpnsFound -or $terraformSpnsFound.Count -eq 0) {
        throw "terraform app not found with name '$($settings.terraform.clientAppName)'"
    }
    elseif ($terraformSpnsFound.Count -gt 1) {
        throw "duplicated app found with name '$($settings.terraform.clientAppName)'"
    }
    else {
        $terraformSpn = $terraformSpnsFound[0]
    }

    $terraformSpnPwd = TryGetSecret -VaultName $settings.kv.name -SecretName $settings.terraform.clientSecret
    if ($null -eq $terraformSpnPwd) {
        throw "Unable to find pwd for terraform spn '$($settings.terraform.clientAppName)'"
    }
    $terraformSpnPwdValue = $terraformSpnPwd.value
    $settings.terraform["spn"] = @{
        appId    = $terraformSpn.appId
        pwd      = $terraformSpnPwdValue
        objectId = $terraformSpn.objectId
    }
}


UsingScope("Create SSL cert") {
    $DomainName = "*.$($settings.dns.name)"
    $VaultName = $settings.kv.name
    $certFile = "~/.acme.sh/\$($DomainName)/\$($DomainName).cer"
    $keyFile = "~/.acme.sh/\$($DomainName)/\$($DomainName).key"
    $caCertFile = "~/.acme.sh/\$($DomainName)/ca.cer"

    $certContent = Get-Content -LiteralPath $certFile -Raw
    $keyContent = Get-Content -LiteralPath $keyFile -Raw
    $caCertContent = Get-Content -LiteralPath $caCertFile -Raw

    $CertSecret = "sslcert-$($DomainName.Replace('*.','').Replace('.','-'))"
    $sslCertSecretYaml = @"
---
apiVersion: v1
kind: Secret
metadata:
    name: $($CertSecret)
    namespace: default
data:
    tls.crt: $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($certContent)))
    tls.key: $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($keyContent)))
    ca.crt: $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($caCertContent)))
type: kubernetes.io/tls
"@

    $sslCertYamlFile = "$($CertSecret).secret"
    [System.IO.File]::WriteAllText($sslCertYamlFile, $sslCertSecretYaml)

    az keyvault secret set --vault-name $VaultName --name $CertSecret --file $sslCertYamlFile | Out-Null
    az keyvault secret set --vault-name $BackupVaultName --name $CertSecret --file $sslCertYamlFile | Out-Null

    $sslCertYamlSecret = az keyvault secret show --vault-name $VaultName --name $CertSecret | ConvertFrom-Json
    $sslCertYaml = $sslCertYamlSecret.value
    $genevaSslCertYamlFile = "$($CertSecret).yaml"
    $sslCertYaml | Out-File $genevaSslCertYamlFile -Encoding ascii
    kubectl apply -f $genevaSslCertYamlFile


    $otherK8sNamespaces = @("azds", "xiaodoli", "monitoring", "nginx", "logging")
    $otherK8sNamespaces | ForEach-Object {
        $ns = $_
        Write-Host "Adding secret '$CertSecret' to '$($ns)'" -ForegroundColor Green

        trap {
            kubectl delete secret $CertSecret -n $ns
        }
        kubectl get secret $CertSecret -o yaml --export | kubectl apply --namespace $ns -f -
    }
}


UsingScope("Create DNS secret") {
    LogStep -Message "create k8s secret to store dns credential..."
    $dnsSecret = @{
        tenantId        = $azAccount.tenantId
        subscriptionId  = $azAccount.id
        aadClientId     = $settings.terraform.spn.appId
        aadClientSecret = $settings.terraform.spn.pwd
        resourceGroup   = $settings.global.resourceGroup.name
    } | ConvertTo-JSON -Compress

    $secretValue = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($dnsSecret))
    $k8sSecret = @"
apiVersion: v1
kind: Secret
metadata:
    name: external-dns-config-file
data:
    azure.json: $secretValue
type: Opaque
"@

    $k8sSecret | kubectl apply --namespace default -f -
    $k8sSecret | kubectl apply --namespace nginx -f -
}

param(
    [string]$DomainName="*.1es.io",
    [string]$VaultName="xiaodoli-bedrock-kv"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

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
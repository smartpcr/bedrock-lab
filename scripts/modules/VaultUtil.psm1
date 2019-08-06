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
    try {
        if ($null -ne $secretsFound -or $secretsFound.Count -eq 0) {
            $secretsFound = $false
        }
        else {
            if ($null -ne $secretsFound[0].value -and ([string]$secretsFound[0].value).Length -gt 0) {
                $secretIsFound = $true
            }
        }
    }
    catch {
        $secretIsFound = $false
    }

    if (!$secretIsFound) {
        $prng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
        $bytes = New-Object Byte[] 30
        $prng.GetBytes($bytes)
        $password = [System.Convert]::ToBase64String($bytes) + "!@1wW" #  ensure we meet password requirements
        az keyvault secret set --vault-name $VaultName --name $SecretName --value $password | Out-Null
        $res = az keyvault secret show --vault-name $VaultName --name $SecretName | ConvertFrom-Json
        return $res
    }

    $res = az keyvault secret show --vault-name $VaultName --name $SecretName | ConvertFrom-Json
    if ($res) {
        return $res
    }
}
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
    if ($null -ne $secretsFound -or $secretsFound.Count -eq 0) {
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
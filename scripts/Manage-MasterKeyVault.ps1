param(
    [string]$VaultName = "xiaodong-kv",
    [string]$ResourceGroupName = "xiaodong-shared-rg"
)

Write-Host "Turn on soft-delete"
az resource update --id $(az keyvault show --name $VaultName -o tsv | awk '{print $1}') --set properties.enableSoftDelete=true

# TODO: setup firewall rules
# TODO: turn on diagnostics logging

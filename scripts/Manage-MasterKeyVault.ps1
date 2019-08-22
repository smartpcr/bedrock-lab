param(
    [string]$VaultName = "xiaodong-kv",
    [string]$ResourceGroupName = "xiaodong-shared-rg"
)

Write-Host "Turn on soft-delete"
az resource update --id $(az keyvault show --name $VaultName -o tsv | awk '{print $1}') --set properties.enableSoftDelete=true

# TODO: setup firewall rules
# TODO: turn on diagnostics logging
kubectl create secret docker-registry acr-auth `
        -n default `
        --docker-server=xiaodongacr.azurecr.io `
        --docker-username=xiaodongacr `
        --docker-password="oC97I2bHuA/qWlmLLT7CeyOIN/IS4bCw" `
        --docker-email="xiaodoli@microsoft.com" | Out-Null
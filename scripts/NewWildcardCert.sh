# NOTE: this script assumes acme.sh is installed
export AZUREDNS_SUBSCRIPTIONID="{{.Values.global.subscriptionId}}"
export AZUREDNS_TENANTID="{{.Values.global.tenantId}}"
export AZUREDNS_APPID="{{.Values.terraform.spn.appId}}"
export AZUREDNS_CLIENTSECRET="{{.Values.terraform.spn.pwd}}"
export DOMAIN="*.{{.Values.dns.name}}"
export VAULT_NAME="{{.Values.kv.name}}"
export KUBECONFIG="./output/admin_kube_config"

 ~/.acme.sh/acme.sh --issue --dns dns_azure -d $DOMAIN --debug


if [ -f "~/.acme.sh/\\$DOMAIN" ]; then
    echo "found domain cert folder, add them to key vault"
    CLEAN_DOMAIN=$(echo $DOMAIN | sed 's/*.//')
    CA_CERT_SECRET_NAME="$(echo $CLEAN_DOMAIN | sed 's/\./-/')-ca-cert"
    az keyvault secret set --vault-name $VAULT_NAME --name $CA_CERT_SECRET_NAME --file ~/.acme.sh/\\$DOMAIN/ca.cer
    KEY_SECRET_NAME="$(echo $CLEAN_DOMAIN | sed 's/\./-/')-key"
    az keyvault secret set --vault-name $VAULT_NAME --name $KEY_SECRET_NAME --file ~/.acme.sh/\\$DOMAIN/\\$DOMAIN.key
    CER_SECRET_NAME="$(echo $CLEAN_DOMAIN | sed 's/\./-/')-cer"
    az keyvault secret set --vault-name $VAULT_NAME --name $CER_SECRET_NAME --file ~/.acme.sh/\\$DOMAIN/\\$DOMAIN.cer
else
    echo "failed to create cert"
    exit 1
fi
# NOTE: this script assumes acme.sh is installed
export AZUREDNS_SUBSCRIPTIONID="{{.Values.global.subscriptionId}}"
export AZUREDNS_TENANTID="{{.Values.global.tenantId}}"
export AZUREDNS_APPID="{{.Values.terraform.spn.appId}}"
export AZUREDNS_CLIENTSECRET="{{.Values.terraform.spn.pwd}}"
export DOMAIN="*.{{.Values.dns.name}}"

 ~/.acme.sh/acme.sh --issue --dns dns_azure -d $DOMAIN --debug
terraform init

export ARM_SUBSCRIPTION_ID="{{.Values.global.subscriptionId}}"
export ARM_TENANT_ID="{{.Values.global.tenantId}}"
export ARM_CLIENT_ID="{{.Values.terraform.spn.appId}}"
export ARM_CLIENT_SECRET="{{.Values.terraform.spn.pwd}}"

echo "Plan"
terraform plan -var-file="terraform.tfvars"

echo "Apply"
terraform apply -var-file="terraform.tfvars"
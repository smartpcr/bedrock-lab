
export ARM_SUBSCRIPTION_ID="{{.Values.global.subscriptionId}}"
export ARM_TENANT_ID="{{.Values.global.tenantId}}"
export ARM_CLIENT_ID="{{.Values.terraform.spn.appId}}"
export ARM_CLIENT_SECRET="{{.Values.terraform.spn.pwd}}"

echo "terraform init -backend-config=\"backend.tfvars\""
terraform init -backend-config="backend.tfvars"

export storage_account_name="{{.Values.terraform.backend.storageAccount}}"
export container_name="{{.Values.terraform.backend.containerName}}"
export key="{{.Values.terraform.backend.key}}"
export access_key="{{.Values.terraform.backend.accessKey}}"

echo "terraform plan -var-file=\"terraform.tfvars\""
terraform plan -var-file="terraform.tfvars"

echo "terraform apply -var-file=\"terraform.tfvars\""
terraform apply -var-file="terraform.tfvars"
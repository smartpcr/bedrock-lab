terraform {
  backend "azurerm" {}
}

module "provider" {
  source = "github.com/smartpcr/bedrock/cluster/azure/provider"
}

resource "azurerm_resource_group" "cluster_rg" {
  name     = "${var.resource_group_name}"
  location = "${var.resource_group_location}"
}

module "aks-gitops" {
  source = "github.com/smartpcr/bedrock/cluster/azure/aks-gitops"

  # aks cluster
  ssh_public_key           = "${var.ssh_public_key}"
  resource_group_location  = "${var.resource_group_location}"
  resource_group_name      = "${azurerm_resource_group.cluster_rg.name}"
  service_principal_id     = "${var.service_principal_id}"
  service_principal_secret = "${var.service_principal_secret}"
  server_app_id            = "${var.server_app_id}"
  server_app_secret        = "${var.server_app_secret}"
  client_app_id            = "${var.client_app_id}"
  tenant_id                = "${var.tenant_id}"
  agent_vm_count           = "${var.agent_vm_count}"
  agent_vm_size            = "${var.agent_vm_size}"
  cluster_name             = "${var.cluster_name}"
  dns_prefix               = "${var.dns_prefix}"
  service_cidr             = "${var.service_cidr}"
  dns_ip                   = "${var.dns_ip}"
  docker_cidr              = "${var.docker_cidr}"
  oms_agent_enabled        = "${var.oms_agent_enabled}"
  enable_dev_spaces        = "${var.enable_dev_spaces}"
  space_name               = "${var.space_name}"
  dashboard_cluster_role   = "${var.dashboard_cluster_role}"

  # aks role assignment
  aks_owners       = "${var.aks_owners}"
  aks_contributors = "${var.aks_contributors}"
  aks_readers      = "${var.aks_readers}"

  # flux
  enable_flux               = "${var.enable_flux}"
  flux_recreate             = "${var.flux_recreate}"
  kubeconfig_recreate       = "${var.kubeconfig_recreate}"
  gc_enabled                = "${var.gc_enabled}"
  acr_enabled               = "${var.acr_enabled}"
  gitops_ssh_url            = "${var.gitops_ssh_url}"
  gitops_ssh_key            = "${var.gitops_ssh_key}"
  gitops_path               = "${var.gitops_path}"
  gitops_poll_interval      = "${var.gitops_poll_interval}"
  gitops_url_branch         = "${var.gitops_url_branch}"
  create_helm_operator      = "${var.create_helm_operator}"
  create_helm_operator_crds = "${var.create_helm_operator_crds}"

  # kv-reader
  vault_name            = "${var.vault_name}"
  vault_reader_identity = "${var.vault_reader_identity}"
  aks_cluster_spn_name  = "${var.aks_cluster_spn_name}"
}

module "acr" {
  source = "github.com/smartpcr/bedrock/cluster/azure/acr"

  resource_group_name  = "${var.resource_group_name}"
  location             = "${var.resource_group_location}"
  name                 = "${var.acr_name}"
  vault_name           = "${var.vault_name}"
  acr_auth_secret_name = "${var.acr_auth_secret_name}"
  email                = "${var.acr_email}"
  alternate_location   = "${var.acr_failover_location}"
}

module "dns" {
  source = "github.com/smartpcr/bedrock/cluster/azure/dns"

  resource_group_name         = "${var.resource_group_name}"
  location                    = "${var.resource_group_location}"
  name                        = "${var.dns_zone_name}"
  service_principal_object_id = "${var.service_principal_object_id}"
  caa_issuer                  = "${var.dns_caa_issuer}"
}

# module "cosmosdb" {
#   source = "github.com/smartpcr/bedrock/cluster/azure/cosmos-sqldb"

#   resource_group_name   = "${var.resource_group_name}"
#   location              = "${var.resource_group_location}"
#   cosmos_db_account     = "${var.cosmos_db_account}"
#   alt_location          = "${var.alt_location}"
#   cosmos_db_name        = "${var.cosmos_db_name}"
#   cosmos_db_collections = "${var.cosmos_db_collections}"
#   allowed_ip_ranges     = "${var.allowed_ip_ranges}"
# }

module "app-insights" {
  source = "github.com/smartpcr/bedrock/cluster/azure/app-insights"

  resource_group_name             = "${var.resource_group_name}"
  location                        = "${var.resource_group_location}"
  name                            = "${var.app_insights_name}"
  vault_name                      = "${var.vault_name}"
  instrumentation_key_secret_name = "${var.app_insights_instrumentation_key_secret_name}"
  app_id_secret_name              = "${var.app_insights_app_id_secret_name}"
}

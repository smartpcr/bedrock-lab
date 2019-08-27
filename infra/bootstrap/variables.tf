###########################
# global
###########################
variable "service_principal_object_id" {
  type        = "string"
  description = "service principal object id who can read and write dns text records"
}

variable "resource_group_name" {
  type = "string"
}

variable "resource_group_location" {
  type = "string"
}

###########################
# aks
###########################
variable "agent_vm_count" {
  type    = "string"
  default = "3"
}

variable "agent_vm_size" {
  type    = "string"
  default = "Standard_D2s_v3"
}

variable "acr_enabled" {
  type    = "string"
  default = "true"
}

variable "gc_enabled" {
  type    = "string"
  default = "true"
}

variable "cluster_name" {
  type = "string"
}

variable "dns_prefix" {
  type = "string"
}

variable "ssh_public_key" {
  type = "string"
}

variable "service_principal_id" {
  type = "string"
}

variable "service_principal_secret" {
  type = "string"
}

variable "server_app_id" {
  type        = "string"
  description = "(Required) The Server ID of an Azure Active Directory Application. Changing this forces a new resource to be created."
}

variable "client_app_id" {
  type        = "string"
  description = "(Required) The Client ID of an Azure Active Directory Application. Changing this forces a new resource to be created."
}

variable "server_app_secret" {
  type        = "string"
  description = "(Required) The Server Secret of an Azure Active Directory Application. Changing this forces a new resource to be created."
}

variable "tenant_id" {
  type        = "string"
  description = "(Optional) The Tenant ID used for Azure Active Directory Application. If this isn't specified the Tenant ID of the current Subscription is used. Changing this forces a new resource to be created."
}

variable "vnet_name" {
  type = "string"
}

variable "service_cidr" {
  default     = "10.0.0.0/16"
  description = "Used to assign internal services in the AKS cluster an IP address. This IP address range should be an address space that isn't in use elsewhere in your network environment. This includes any on-premises network ranges if you connect, or plan to connect, your Azure virtual networks using Express Route or a Site-to-Site VPN connections."
  type        = "string"
}

variable "dns_ip" {
  default     = "10.0.0.10"
  description = "should be the .10 address of your service IP address range"
  type        = "string"
}

variable "docker_cidr" {
  default     = "172.17.0.1/16"
  description = "IP address (in CIDR notation) used as the Docker bridge IP address on nodes. Default of 172.17.0.1/16."
}

variable "address_space" {
  description = "The address space that is used by the virtual network."
  default     = "10.10.0.0/16"
}

variable "subnet_prefixes" {
  description = "The address prefix to use for the subnet."
  default     = ["10.10.1.0/24"]
}

variable "network_policy" {
  default     = "azure"
  description = "Network policy to be used with Azure CNI. Either azure or calico."
}

variable "oms_agent_enabled" {
  type    = "string"
  default = "true"
}

###########################
# aks addon/rbac
###########################
variable "dashboard_cluster_role" {
  type = "string"
}

variable "enable_dev_spaces" {
  type    = "string"
  default = "true"
}

variable "space_name" {
  type    = "string"
  default = "xiaodong"
}

variable "aks_owners" {
  type        = "string"
  description = "comma separated aad user object id who are granted to cluster cluster admins"
  default     = ""
}

variable "aks_contributors" {
  type        = "string"
  description = "comma separated aad group object id who are contributors to aks"
  default     = ""
}

variable "aks_readers" {
  type        = "string"
  description = "comma separated aad group object id who are readers to aks"
  default     = ""
}

###########################
# flux
###########################
variable "gitops_poll_interval" {
  type    = "string"
  default = "5m"
}

variable "enable_flux" {
  type    = "string"
  default = "true"
}

variable "flux_recreate" {
  description = "Make any change to this value to trigger the recreation of the flux execution script."
  type        = "string"
  default     = ""
}

variable "kubeconfig_recreate" {
  description = "Any change to this variable will recreate the kube config file to local disk."
  type        = "string"
  default     = ""
}

variable "gitops_ssh_url" {
  type = "string"
}

variable "gitops_ssh_key" {
  type = "string"
}

variable "gitops_path" {
  type    = "string"
  default = "generated"
}

variable "gitops_url_branch" {
  type    = "string"
  default = "releases/poc"
}

variable "create_helm_operator" {
  type        = "string"
  description = "create helm operator"
  default     = "true"
}

variable "create_helm_operator_crds" {
  type        = "string"
  description = "create CRDs associated with helm operator"
  default     = "true"
}

###########################
# kv reader
###########################
variable "vault_name" {
  type        = "string"
  description = "name of key vault, must be unique within resource group"
}

variable "vault_reader_identity" {
  type        = "string"
  description = "user assigned identity name that will be granted reader role to key vault"
}

variable "aks_cluster_spn_name" {
  type        = "string"
  description = "name of AKS cluster service principal"
}

###########################
# acr
###########################

variable "acr_name" {
  type        = "string"
  description = "name of acr"
}

variable "acr_auth_secret_name" {
  type        = "string"
  description = "Secret name for username used to login docker"
}

variable "acr_email" {
  type        = "string"
  description = "email of acr owner"
}

variable "acr_failover_location" {
  type        = "string"
  description = "failover location for acr"
  default     = "eastus"
}

###########################
# DNS Zone
###########################
variable "dns_zone_name" {
  type        = "string"
  description = "name of dns zone, redirect traffic under a zone, i.e. dev.1cs.io"
}

variable "dns_caa_issuer" {
  type        = "string"
  description = "name of issuer that can be trusted, i.e. letsencrypt.org"
}

###########################
# CosmosDB
###########################
variable "cosmos_db_account" {
  type        = "string"
  description = "name of cosmosdb account"
}

variable "alt_location" {
  type        = "string"
  description = "The Azure Region which should be used for the alternate location when failed over."
}

variable "consistency_level" {
  type        = "string"
  description = "cosmosdb consistency level: BoundedStaleness, Eventual, Session, Strong, ConsistentPrefix"
  default     = "Session"
}

variable "enable_filewall" {
  type        = "string"
  description = "Specify if firewall rules should be applied"
  default     = "false"
}

variable "allowed_ip_ranges" {
  type        = "string"
  description = "allowed ip range in addition to azure services and azure portal, i.e. 12.54.145.0/24,13.75.0.0/16"
}

variable "cosmos_db_offer_type" {
  type    = "string"
  default = "Standard"
}

variable "cosmos_db_name" {
  type        = "string"
  description = "CosmosDB name"
}

variable "cosmos_db_collections" {
  type        = "string"
  description = "collections are separated by ';', each entry takes the format: collection_name,partiton_key,throughput"
}

###########################
# app insights
###########################
variable "app_insights_name" {
  type        = "string"
  description = "name of app insights"
}

variable "app_insights_instrumentation_key_secret_name" {
  type = "string"
}

variable "app_insights_app_id_secret_name" {
  type = "string"
}

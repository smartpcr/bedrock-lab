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
  default = ""
}

variable "gitops_url_branch" {
  type    = "string"
  default = "master"
}

variable "resource_group_name" {
  type = "string"
}

variable "resource_group_location" {
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
  type = "string"
  description = "(Required) The Server ID of an Azure Active Directory Application. Changing this forces a new resource to be created."
}

variable "client_app_id" {
  type = "string"
  description="(Required) The Client ID of an Azure Active Directory Application. Changing this forces a new resource to be created."
}

variable "server_app_secret" {
  type = "string"
  description="(Required) The Server Secret of an Azure Active Directory Application. Changing this forces a new resource to be created."
}

variable "tenant_id" {
  type = "string"
  description = "(Optional) The Tenant ID used for Azure Active Directory Application. If this isn't specified the Tenant ID of the current Subscription is used. Changing this forces a new resource to be created."
}

variable "gitops_poll_interval" {
  type    = "string"
  default = "5m"
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
  default = "false"
}

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
  type = "string"
  description = "comma separated aad user object id who are granted to cluster cluster admins"
  default = ""
}

variable "aks_contributors" {
  type = "string"
  description = "comma separated aad group object id who are contributors to aks"
  default = ""
}

variable "aks_readers" {
  type = "string"
  description = "comma separated aad group object id who are readers to aks"
  default = ""
}

# DNS Zone
variable "dns_zone_name" {
  type = "string"
  description = "name of dns zone, redirect traffic under a zone, i.e. dev.1cs.io"
}

variable "dns_caa_issuer" {
  type = "string"
  description = "name of issuer that can be trusted, i.e. letsencrypt.org"
}

variable "service_principal_object_id" {
  type = "string"
  description = "service principal object id who can read and write dns text records"
}


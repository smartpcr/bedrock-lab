# rg
resource_group_name="{{.Values.aks.resourceGroup}}"
resource_group_location="{{.Values.aks.location}}"

# kv
vault_name="{{.Values.kv.name}}"
vault_reader_identity = "{{.Values.kv.reader}}"
aks_cluster_spn_name = "{{.Values.terraform.clientAppName}}"

# aks
cluster_name="{{.Values.aks.clusterName}}"
agent_vm_count = "{{.Values.aks.nodeCount}}"
agent_vm_size = "{{.Values.aks.vmSize}}"
dns_prefix="{{.Values.aks.dnsPrefix}}"
service_principal_id = "{{.Values.terraform.spn.appId}}"
service_principal_secret = "{{.Values.terraform.spn.pwd}}"
server_app_id = "{{.Values.aks.server_app_id}}"
server_app_secret = "{{.Values.aks.server_app_secret}}"
client_app_id = "{{.Values.aks.client_app_id}}"
tenant_id = "{{.Values.aks.tenant_id}}"
ssh_public_key = "{{.Values.aks.nodePublicSshKey}}"
vnet_name = "{{.Values.aks.virtualNetwork}}"
dashboard_cluster_role = "cluster_admin"
enable_dev_spaces = "true"
space_name = "xiaodong"

# aks role assignment
aks_owners = "{{.Values.aks.roleAssignments.ownerObjectIds}}"
aks_contributors = "{{.Values.aks.roleAssignments.contributorObjectIds}}"
aks_readers = "{{.Values.aks.roleAssignments.readerObjectIds}}"

# flux
gitops_ssh_url = "{{.Values.gitRepo.repo}}"
gitops_ssh_key = "{{.Values.gitRepo.deployPrivateKeyFile}}"
enable_flux = "true"
flux_recreate = "true"

# acr
acr_name = "{{.Values.acr.name}}"
acr_auth_secret_name = "{{.Values.acr.auth_secret}}"
acr_email = "{{.Values.acr.email}}"

# DNS zone
dns_zone_name = "{{.Values.dns.name}}"
dns_caa_issuer = "{{.Values.dns.caaIssuer}}"
service_principal_object_id = "{{.Values.terraform.spn.objectId}}"

# Cosmos DB
alt_location = "{{.Values.cosmosdb.failOverRegion}}"
allowed_ip_ranges = "{{.Values.cosmosdb.corpIpRanges}}"
consistency_level = "{{.Values.cosmosdb.consistency}}"
cosmos_db_account = "{{.Values.cosmosdb.account}}"
cosmos_db_name = "{{.Values.cosmosdb.db}}"
cosmos_db_collections = "{{.Values.cosmosdb.collectionSettings}}"
enable_filewall = "{{.Values.cosmosdb.enableFirewallRules}}"

# app insights
app_insights_name = "{{.Values.appInsights.name}}"
app_insights_instrumentation_key_secret_name = "{{.Values.appInsights.secrets.instrumentationKey}}"
app_insights_app_id_secret_name = "{{.Values.appInsights.secrets.appId}}"

#--------------------------------------------------------------
# Optional variables - Uncomment to use
#--------------------------------------------------------------
# gitops_url_branch = "release-123"
# gitops_poll_interval = "30s"
# gitops_path = "prod"
# network_policy = "calico"
# oms_agent_enabled = "false"

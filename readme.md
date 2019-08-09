Before git repo and aks cluster can be synchronized, the following must be created first
 - aks cluster
 - deploy flux to aks cluster
 - point flux to git repo

This project does just that, it creates a minimal aks cluster with flux component (based on bedrock)

In addition, the following modification are made to aks cluster:
1. aad integration (server and client app), so that aad user/group can login to dashboard
2. service principal was used for both aks cluster and terraform deployment, it can be authenticated by either password or certificate
3. a few add-ons are enabled: http-application-routing, monitoring, and dev-spaces
4. dashboard is granted cluster-admin role for non-prod (dev, int) cluster, and reader role for prod cluster
5. aad users and groups can be granted contributor/reader role in aks cluster
6. install helm/tiller

## steps
1. modify `setting.yaml` file to point to your subscription, and where you want it to be created
2. run `bootstrap-aks.ps1`
3. navigate to terraform output folder, run `terraform.sh`


## progress

### Bootstrap
| order | task | status |
| -- | -- | -- |
| 1 | provision flux and aks cluster | yes |
| 2 | output admin kube config | yes |
| 3 | integrate aad profile | yes |
| 4 | additional addons (routing, monitoring, devspaces) | yes |
| 5 | grant dashboard access | yes |
| 6 | grant additional aad user and groups | yes |
| 7 | update deploy-key, repo-url in flux settings and enable sync | yes |
| 8 | enable remote tf state using azure blob storage | in-progress |

### HDL for infra
| order | HDL component | status | notes |
| -- | -- | -- | -- |
| 1 | dns zone, nginx, external-dns | in-progress | dns zone handled by azure terraform module, others handled by helm in HDL definition |
| 2 | prometheus-grafana-alert-manager | in-progress | need to deploy all resources to namespace 'prometheus' |
| 3 | fluentd-elasticsearch-kibana | in-progress | make sure requested resource is within limit |
| 4 | aad-pod-identity | no | |
| 5 | cosmosdb | no | |
| 6 | servicebus, kafka | no | |
| 7 | jaeger, app-insights | no | |

### HDL for services (helm)
| order | HDL component | status |
| -- | -- | -- |
| 1 | prod-catalog-api | no |
| 2 | prod-catalog-web | no |
| 3 | prod-catalog-sync-job | no |

### build script to translate HDL to yamls
| order | task | status |
| -- | -- | -- |
| 1 | ADO CI/CD pipeline | no |
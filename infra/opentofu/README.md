# OpenTofu infrastruktura pro jednoduchý web na Google Cloud

Tato konfigurace vytváří bezpečné prostředí v **Google Cloud Platform** nad službou **GKE (Google Kubernetes Engine)**. Nasazuje referenční webovou aplikaci s veřejnou doménou, TLS přes Let's Encrypt, monitoring (Prometheus + Grafana), sběr logů (Elastic stack) a správu tajemství v **HashiCorp Vault**.

## Architektura

- **Síť a bezpečnost**
  - Dedikovaná VPC (`custom mode`) s privátními GKE nodů a sekundárními rozsahy pro pody/služby.
  - Cloud Router + Cloud NAT pro bezpečný odchozí provoz bez veřejných IP na nody.
  - Master Authorized Networks (volitelné) a privátní GKE cluster s aktivním Workload Identity.
- **Compute**
  - GKE standard cluster (`REGULAR` channel), shielded nodes, autoscaling node pool (min 3 / max 6 `e2-standard-4`).
  - Statická externí IP (`google_compute_address`) pro ingress.
- **Ingress & TLS**
  - `ingress-nginx` s předem alokovanou IP, HTTP→HTTPS redirect.
  - `cert-manager` s DNS-01 validací přes Cloud DNS.
- **Aplikace**
  - Nginx deployment s Vault agentem, liveness/readiness probe, omezení schopností.
  - NetworkPolicy propouští příchozí provoz pouze z ingress namespace.
- **Tajemství**
  - HA HashiCorp Vault (Helm chart, Raft storage, injector sidecar).
  - Vault injektuje runtime proměnné do aplikace a připravený hook pro logovací agenty.
- **Monitoring & Logování**
  - `kube-prometheus-stack` (Prometheus, Alertmanager, Grafana).
  - Elastic stack (Elasticsearch 2× replica, Kibana, Filebeat daemonset).
- **DNS**
  - DNS záznam v existující Cloud DNS zóně ukazuje na statickou IP ingressu.

## Požadavky

1. Projekt v GCP a účet s oprávněními `roles/owner` nebo kombinací `compute`, `container`, `dns`, `iam`, `serviceusage`.
2. Servisní účet pro Terraform (doporučeno) a stažený JSON klíč.
3. Existující Cloud DNS zóna pro požadovanou doménu (např. `example.com.`).
4. Servisní účet pro `cert-manager` s rolí `dns.admin` (JSON klíč uložený ve Vaultu / Secretu).
5. Nainstalovaný `gke-gcloud-auth-plugin`, `gcloud`, `kubectl`, `helm`.

## Nasazení

1. **Aktivace API** – Terraform zajistí povolení požadovaných služeb (`compute`, `container`, `dns`, `monitoring`, `logging`, `iam`).
2. **Secret pro cert-manager** – vytvořte v namespace `cert-manager` secret s Google service account klíčem:

   ```bash
   kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
   kubectl create secret generic clouddns-dns01 \
     --namespace cert-manager \
     --from-file=key.json=/cesta/k/service-account.json
   ```

   (alternativně nechte Vault injektovat prostřednictvím `vault agent`).

3. **Konfigurace `terraform.tfvars`** – příklad:

   ```hcl
   project_name                           = "portfolio"
   gcp_project_id                         = "my-gcp-project"
   gcp_region                             = "europe-west1"
   gcp_zones                              = ["europe-west1-b", "europe-west1-c"]
   gcp_credentials_json                   = file("sa-terraform.json")
   domain_name                            = "www.example.com"
   dns_managed_zone                       = "example-com"
   acme_email                             = "ops@example.com"
   gke_master_authorized_networks = [
     { cidr = "203.0.113.24/32", label = "Office" }
   ]
   tags = {
     environment = "production"
     team        = "web"
   }
   ```

4. **Spuštění OpenTofu**

   ```bash
   tofu init
   tofu plan
   tofu apply
   ```

5. **Kubeconfig** – vygenerovaný výstup `kubeconfig` obsahuje GKE exec plugin. Uložte ho do souboru a nastavte `KUBECONFIG`, nebo použijte `gcloud container clusters get-credentials ...`.

## Vault a práce s tajemstvími

- Po nasazení inicializujte Vault (`vault operator init`) a uložte recovery klíče mimo repozitář.
- Pro autentizaci Kubernetes backendu použijte service account:

  ```bash
  kubectl create serviceaccount vault-auth -n vault
  kubectl apply -n vault -f - <<'YAML'
  apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRoleBinding
  metadata:
    name: vault-auth
  subjects:
    - kind: ServiceAccount
      name: vault-auth
      namespace: vault
  roleRef:
    kind: ClusterRole
    name: system:auth-delegator
    apiGroup: rbac.authorization.k8s.io
  YAML
  ```

- Nastavte Kubernetes auth v Vaultu:

  ```bash
  vault auth enable kubernetes
  vault write auth/kubernetes/config \
    token_reviewer_jwt="$(kubectl create token vault-auth -n vault)" \
    kubernetes_host="$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}')" \
    kubernetes_ca_cert="$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 --decode)"

  vault write auth/kubernetes/role/web-app \
    bound_service_account_names=default \
    bound_service_account_namespaces=web \
    policies=web-app \
    ttl=24h
  ```

- Vytvořte politiky a tajemství:
  - `secret/data/web/app` → aplikační tajemství (`env`, `secret`).
  - `secret/data/logging/filebeat` → přihlašovací údaje k Elasticsearch pro Filebeat.

- Vault agent injektuje proměnné do Podů (`annotations` v manifestu aplikace a Filebeatu lze dále rozšířit o templaty).

## Monitoring a logování

- Výstup `grafana_admin_password` obsahuje náhodně generované heslo.
- Elastic stack běží v namespace `logging`:
  - Přidejte Vault politiku, která Filebeatu vrátí `username/password`.
  - Pokud chcete centralizovanou autentizaci, zvažte nasazení **Elastic Agent Fleet**.
- Upravte `kube-prometheus-stack` hodnoty (alerty, retention) dle provozu.

## Bezpečnostní doporučení

- V `gke_master_authorized_networks` ponechte pouze adresy administrátorských sítí; ostatní přístupy řešte přes IAP / VPN.
- Přidejte **Binary Authorization** nebo aspoň `imagePolicyWebhook`, pokud spravujete produkční buildy.
- Aktivujte **routování audit logů** (Cloud Logging export do vlastní identity nebo SIEM).
- Rozdělte workloady do více node poolů (např. logování na separátních disk type `ssd`).
- Pro cert-manager uložte GCP servisní účet do Vaultu a injektujte nami místo statického Secretu.

## Odhad měsíčních nákladů (europe-west1, bez slev)

- GKE control plane: zdarma (standard cluster).
- Node pool 3× `e2-standard-4` (~$0.134 / hodina) → ~**$290 / měsíc** při kontinuálním běhu.
- SSD persistent volumes (Vault 15 Gi, Elastic 2×20 Gi, náhodné) → ~**$15 / měsíc**.
- Cloud NAT, statická IP, DNS a síťové přenosy → orientačně **$10–20 / měsíc** podle provozu.

Celkem tedy cca **$320 / měsíc** při minimálním vytížení. Využijte committed use slevy nebo preemptible nody pro snížení nákladů.

## Další kroky

1. Přidejte `PodSecurityStandards` (PSP náhrada) pomocí `PodSecurity` admission nebo Kyverno/Gatekeeper.
2. Zapojte `External Secrets Operator`, pokud chcete Vault → K8s synchronizaci bez anotací.
3. Definujte alerting kanály (PagerDuty, Slack) a metriky SLO přímo v Grafaně.
4. Připravte zálohy pro Vault Raft storage a Elastic (snapshoty do GCS).


uprava kvuli actions
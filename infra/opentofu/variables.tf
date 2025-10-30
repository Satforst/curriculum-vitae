variable "project_name" {
  description = "Jmeno projektu pouzite v nazvech zdroju."
  type        = string
  default     = "cv-web"
}

variable "gcp_project_id" {
  description = "ID projektu v Google Cloud, kde poběží infrastruktura."
  type        = string
}

variable "gcp_region" {
  description = "Region Google Cloud (napr. europe-west1)."
  type        = string
  default     = "europe-west1"
}

variable "gcp_zones" {
  description = "Seznam zón, ve kterých budou GKE nody (pokud prázdné, použije se výchozí zóna regionu)."
  type        = list(string)
  default     = []
}

variable "gcp_credentials_json" {
  description = "Obsah JSON s privátním klíčem servisního účtu s oprávněními pro GCP zdroje. Pokud neuvedeno, použije se ADC (např. proměnná GOOGLE_APPLICATION_CREDENTIALS)."
  type        = string
  default     = null
  sensitive   = true
}

variable "vpc_cidr_block" {
  description = "Primární CIDR blok pro VPC síť."
  type        = string
  default     = "10.20.0.0/16"
}

variable "gke_pod_cidr_block" {
  description = "CIDR blok pro pod sítě (sekundární rozsah)."
  type        = string
  default     = "10.21.0.0/16"
}

variable "gke_services_cidr_block" {
  description = "CIDR blok pro služby (sekundární rozsah)."
  type        = string
  default     = "10.22.0.0/20"
}

variable "gke_master_ipv4_cidr" {
  description = "CIDR blok pro master endpoint privátního clustru."
  type        = string
  default     = "172.16.0.0/28"
}

variable "gke_master_authorized_networks" {
  description = "Seznam autorizovaných CIDR pro přístup na Kubernetes API server."
  type = list(object({
    cidr  = string
    label = optional(string)
  }))
  default = []
}

variable "gke_release_channel" {
  description = "Release channel GKE (RAPID, REGULAR, STABLE)."
  type        = string
  default     = "REGULAR"
}

variable "gke_node_machine_type" {
  description = "Typ virtuálního stroje pro node pool."
  type        = string
  default     = "e2-standard-4"
}

variable "gke_node_disk_size_gb" {
  description = "Velikost datového disku pro nody (v GB)."
  type        = number
  default     = 100
}

variable "gke_min_node_count" {
  description = "Minimální počet nodů v autoscaling node poolu."
  type        = number
  default     = 3
}

variable "gke_max_node_count" {
  description = "Maximální počet nodů v autoscaling node poolu."
  type        = number
  default     = 6
}

variable "node_tags" {
  description = "GCP network tagy aplikované na GKE nody."
  type        = list(string)
  default     = []
}

variable "domain_name" {
  description = "FQDN webove aplikace, ktery bude smerovat na ingress."
  type        = string
}

variable "dns_managed_zone" {
  description = "Existující Cloud DNS managed zone, kde se vytvoří DNS záznam."
  type        = string
}

variable "dns_project_id" {
  description = "Projekt, ve kterém se nachází Cloud DNS managed zone (pokud jiné než gcp_project_id)."
  type        = string
  default     = null
}

variable "clouddns_service_account_secret_name" {
  description = "Název Kubernetes Secretu v namespace cert-manager obsahujícího JSON klíč pro Google Cloud DNS (key.json)."
  type        = string
  default     = "clouddns-dns01"
}

variable "clouddns_service_account_secret_key" {
  description = "Klíč v rámci Secretu, který obsahuje JSON klíč servisního účtu."
  type        = string
  default     = "key.json"
}

variable "enable_monitoring" {
  description = "Povoleni instalace Promethea a Grafany."
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Povoleni instalace Elastic stacku pro logovani."
  type        = bool
  default     = true
}

variable "acme_email" {
  description = "Kontaktni email pro registraci Let's Encrypt, pokud se pouzije cert-manager."
  type        = string
  default     = "admin@example.com"
}

variable "enable_cert_manager" {
  description = "Povoleni instalace cert-manageru pro automaticke vystavovani TLS certifikatu."
  type        = bool
  default     = true
}

variable "vault_helm_chart_version" {
  description = "Verze Helm chartu HashiCorp Vault."
  type        = string
  default     = "0.25.0"
}

variable "ingress_controller_chart_version" {
  description = "Verze Helm chartu pro ingress-nginx."
  type        = string
  default     = "4.10.0"
}

variable "prometheus_stack_chart_version" {
  description = "Verze Helm chartu kube-prometheus-stack."
  type        = string
  default     = "56.3.0"
}

variable "elastic_operator_chart_version" {
  description = "Verze Helm chartu Elastic ECK operatoru."
  type        = string
  default     = "2.10.0"
}

variable "tags" {
  description = "Dodatecne tagy aplikovane na cloudove zdroje (mapa key => value)."
  type        = map(string)
  default     = {}
}

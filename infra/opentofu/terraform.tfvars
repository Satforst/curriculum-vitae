# Identifikace projektu a základní parametry
project_name   = "CV website"
gcp_project_id = "cv-website-476613"
gcp_region     = "europe-west1"
gcp_zones      = ["europe-west1-b", "europe-west1-c"]

# Autentizace Terraformu (JSON klíč servisního účtu). Pokud používáte ADC, ponechte null.
gcp_credentials_json = file("sa-terraform.json")

# Síťová konfigurace GKE (ponechte výchozí CIDR bloky, pokud nevíte)
vpc_cidr_block          = "10.20.0.0/16"
gke_pod_cidr_block      = "10.21.0.0/16"
gke_services_cidr_block = "10.22.0.0/20"
gke_master_ipv4_cidr    = "172.16.0.0/28"
gke_master_authorized_networks = [
  {
    cidr  = "203.0.113.24/32"
    label = "office"
  }
]

# Parametry node poolu
gke_release_channel   = "REGULAR"
gke_node_machine_type = "e2-standard-4"
gke_node_disk_size_gb = 100
gke_min_node_count    = 3
gke_max_node_count    = 6
node_tags             = ["gke-node", "web"]

# DNS a TLS
domain_name      = "www.machacek.karel.guru"
dns_managed_zone = "machacek-karel-guru-zone"
dns_project_id   = null
acme_email       = "web@pocitacestraznice.cz"

# Kubernetes secret s klíčem pro Cloud DNS (pokud měníte jméno/klíč, upravte i v cert_manager.tf)
clouddns_service_account_secret_name = "clouddns-dns01"
clouddns_service_account_secret_key  = "key.json"

# Feature flagy pro volitelné komponenty
enable_cert_manager = true
enable_monitoring   = true
enable_logging      = true

# Tagy aplikované na GCP zdroje (mapa klíč => hodnota)
tags = {
  environment = "production"
  team        = "web"
}

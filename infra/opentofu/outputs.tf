output "cluster_name" {
  description = "Nazev vytvoreneho Kubernetes clustru."
  value       = google_container_cluster.main.name
}

output "kubeconfig" {
  description = "Kubeconfig pro pristup do clustru."
  value = yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = google_container_cluster.main.name
      cluster = {
        certificate-authority-data = google_container_cluster.main.master_auth[0].cluster_ca_certificate
        server                     = "https://${google_container_cluster.main.endpoint}"
      }
    }]
    contexts = [{
      name = "gke-${google_container_cluster.main.name}"
      context = {
        cluster = google_container_cluster.main.name
        user    = "gke-user"
      }
    }]
    "current-context" = "gke-${google_container_cluster.main.name}"
    users = [{
      name = "gke-user"
      user = {
        exec = {
          apiVersion = "client.authentication.k8s.io/v1beta1"
          command    = "gke-gcloud-auth-plugin"
        }
      }
    }]
  })
  sensitive = true
}

output "load_balancer_ipv4" {
  description = "Verejna IPv4 adresa load balanceru."
  value       = google_compute_address.ingress.address
}

output "grafana_admin_password" {
  description = "Generovane heslo pro uzivatele Grafana admin."
  value       = random_password.grafana_admin.result
  sensitive   = true
}

output "site_url" {
  description = "URL verejne dostupne webove aplikace."
  value       = "https://${var.domain_name}"
}

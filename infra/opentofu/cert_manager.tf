resource "kubernetes_manifest" "letsencrypt_clusterissuer" {
  count = var.enable_cert_manager ? 1 : 0

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-production"
    }
    spec = {
      acme = {
        email  = var.acme_email
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-production"
        }
        solvers = [{
          dns01 = {
            cloudDNS = {
              project = var.gcp_project_id
              serviceAccountSecretRef = {
                name = var.clouddns_service_account_secret_name
                key  = var.clouddns_service_account_secret_key
              }
            }
          }
        }]
      }
    }
  }

  depends_on = [
    helm_release.cert_manager
  ]
}

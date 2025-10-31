resource "random_password" "grafana_admin" {
  length           = 20
  override_special = "!@#%^*-_=+"
  special          = true
}

locals {
  ingress_values = {
    controller = {
      replicaCount = max(2, var.gke_min_node_count)
      service = {
        annotations = {
          "networking.gke.io/load-balancer-type" = "External"
          "cloud.google.com/neg"                 = jsonencode({ ingress = true })
        }
        externalTrafficPolicy = "Local"
        loadBalancerIP        = google_compute_address.ingress.address
      }
    }
  }

  vault_values = {
    global = {
      tlsDisable = false
    }
    injector = {
      enabled = true
    }
    server = {
      ha = {
        enabled  = true
        replicas = 1
        raft = {
          enabled   = true
          setNodeId = true
          config    = <<-EOT
            ui = true

            listener "tcp" {
              address         = "0.0.0.0:8200"
              cluster_address = "0.0.0.0:8201"
              tls_cert_file      = "/vault/userconfig/tls/tls.crt"
              tls_key_file       = "/vault/userconfig/tls/tls.key"
              tls_client_ca_file = "/vault/userconfig/tls/ca.crt"
            }

            storage "raft" {
              path = "/vault/data"
            }

            service_registration "kubernetes" {}
          EOT
        }
      }
      dataStorage = {
        enabled = true
        size    = "10Gi"
      }
      auditStorage = {
        enabled = true
        size    = "5Gi"
      }
      standalone = {
        enabled = false
      }
      extraVolumes = [
        {
          type = "secret"
          name = "vault-server-tls"
          path = "tls"
        }
      ]
      extraEnvironmentVars = {
        VAULT_CACERT = "/vault/userconfig/tls/ca.crt"
        VAULT_TLSCERT = "/vault/userconfig/tls/tls.crt"
        VAULT_TLSKEY  = "/vault/userconfig/tls/tls.key"
      }
    }
  }

  prometheus_values = {
    grafana = {
      adminPassword = random_password.grafana_admin.result
      ingress = {
        enabled = false
      }
    }
    prometheus = {
      prometheusSpec = {
        retention                               = "15d"
        retentionSize                           = "10GiB"
        scrapeInterval                          = "30s"
        serviceMonitorSelectorNilUsesHelmValues = false
      }
    }
    alertmanager = {
      alertmanagerSpec = {
        replicas = 2
      }
    }
  }

  elasticsearch_values = {
    replicas           = 2
    minimumMasterNodes = 1
    volumeClaimTemplate = {
      accessModes = ["ReadWriteOnce"]
      resources = {
        requests = {
          storage = "20Gi"
        }
      }
    }
    esJavaOpts = "-Xms1g -Xmx1g"
    resources = {
      requests = {
        cpu    = "500m"
        memory = "2Gi"
      }
      limits = {
        cpu    = "1"
        memory = "4Gi"
      }
    }
  }

  kibana_values = {
    replicas = 1
    resources = {
      requests = {
        cpu    = "250m"
        memory = "1Gi"
      }
      limits = {
        cpu    = "500m"
        memory = "2Gi"
      }
    }
    elasticsearchHosts = ["http://elasticsearch-master.logging.svc.cluster.local:9200"]
  }

  filebeat_values = {
    daemonset = {
      filebeatConfig = {
        "filebeat.yml" = yamlencode({
          filebeat = {
            autodiscover = {
              providers = [{
                type  = "kubernetes"
                hints = { "enabled" = true }
              }]
            }
          }
          output = {
            elasticsearch = {
              hosts    = ["http://elasticsearch-master.logging.svc.cluster.local:9200"]
              username = "${var.project_name}-filebeat"
              password = ""
            }
          }
          setup = {
            ilm = { enabled = false }
          }
        })
      }
    }
  }

  cert_manager_values = {
    installCRDs = true
    extraDeploy = [
      yamlencode({
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
      }),
      yamlencode({
        apiVersion = "cert-manager.io/v1"
        kind       = "Certificate"
        metadata = {
          name      = "vault-server-tls"
          namespace = "vault"
        }
        spec = {
          secretName = "vault-server-tls"
          duration   = "2160h" # 90 days
          renewBefore = "360h" # 15 days
          issuerRef = {
            name = "letsencrypt-production"
            kind = "ClusterIssuer"
          }
          dnsNames = [
            "vault.vault.svc",
            "vault.vault.svc.cluster.local"
          ]
        }
      })
    ]
  }
}

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.ingress_controller_chart_version
  namespace  = kubernetes_namespace.ingress.metadata[0].name

  values = [yamlencode(local.ingress_values)]

  depends_on = [
    google_container_node_pool.primary,
    google_compute_address.ingress
  ]
}

resource "helm_release" "vault" {
  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = var.vault_helm_chart_version
  namespace  = kubernetes_namespace.vault.metadata[0].name

  values = [yamlencode(local.vault_values)]

  depends_on = [
    kubernetes_namespace.vault
  ]
}

resource "helm_release" "cert_manager" {
  count      = var.enable_cert_manager ? 1 : 0
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.13.3"
  namespace  = kubernetes_namespace.cert_manager[count.index].metadata[0].name

  values = [yamlencode(local.cert_manager_values)]

  depends_on = [
    kubernetes_namespace.cert_manager
  ]
}

resource "helm_release" "kube_prometheus_stack" {
  count      = var.enable_monitoring ? 1 : 0
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.prometheus_stack_chart_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [yamlencode(local.prometheus_values)]

  depends_on = [
    kubernetes_namespace.monitoring
  ]
}

resource "helm_release" "elasticsearch" {
  count      = var.enable_logging ? 1 : 0
  name       = "elasticsearch"
  repository = "https://helm.elastic.co"
  chart      = "elasticsearch"
  version    = "8.11.0"
  namespace  = kubernetes_namespace.logging.metadata[0].name

  values = [yamlencode(local.elasticsearch_values)]

  depends_on = [
    kubernetes_namespace.logging
  ]
}

resource "helm_release" "kibana" {
  count      = var.enable_logging ? 1 : 0
  name       = "kibana"
  repository = "https://helm.elastic.co"
  chart      = "kibana"
  version    = "8.11.0"
  namespace  = kubernetes_namespace.logging.metadata[0].name

  values = [yamlencode(local.kibana_values)]

  depends_on = [
    helm_release.elasticsearch
  ]
}

resource "helm_release" "filebeat" {
  count      = var.enable_logging ? 1 : 0
  name       = "filebeat"
  repository = "https://helm.elastic.co"
  chart      = "filebeat"
  version    = "8.11.0"
  namespace  = kubernetes_namespace.logging.metadata[0].name

  values = [yamlencode(local.filebeat_values)]

  depends_on = [
    helm_release.elasticsearch,
    kubernetes_namespace.logging
  ]
}

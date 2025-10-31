locals {
  web_image = "nginx:1.25-alpine"
  web_ingress_annotations = merge(
    {
      "nginx.ingress.kubernetes.io/force-ssl-redirect" = "true"
    },
    var.enable_cert_manager ? {
      "cert-manager.io/cluster-issuer" = "letsencrypt-production"
    } : {}
  )
}

resource "kubernetes_config_map" "web_content" {
  count = var.enable_web ? 1 : 0

  metadata {
    name      = "web-content"
    namespace = kubernetes_namespace.web[count.index].metadata[0].name
    labels = {
      "app" = "web"
    }
  }

  data = {
    "index.html" = <<-EOT
      <!DOCTYPE html>
      <html lang="cs">
      <head>
        <meta charset="utf-8"/>
        <title>${var.project_name} – jednoduchá stránka</title>
        <style>
          body { font-family: Arial, sans-serif; margin: 3rem; line-height: 1.5; background: #f3f6fa; color: #1c2530; }
          article { max-width: 40rem; margin: 0 auto; background: #fff; padding: 2.5rem; border-radius: 12px; box-shadow: 0 12px 32px rgba(24,39,75,0.1); }
          h1 { margin-top: 0; font-size: 2.4rem; }
          p { font-size: 1.1rem; }
          a { color: #1b6ac9; text-decoration: none; }
          a:hover { text-decoration: underline; }
        </style>
      </head>
      <body>
        <article>
          <h1>Vítejte na ${var.project_name}</h1>
          <p>Toto je referenční statická stránka nasazená v Kubernetes clustru spravovaném přes OpenTofu.</p>
          <p>Konfigurace clustru dodržuje bezpečnostní best practices, monitoring Prometheus + Grafana a logování přes Elastic stack.</p>
          <p>Další kroky: nahraďte tento obsah vlastním front-endem a spravujte tajemství přes Vault.</p>
        </article>
      </body>
      </html>
    EOT
  }
}

resource "kubernetes_deployment" "web" {
  count = var.enable_web ? 1 : 0

  metadata {
    name      = "web"
    namespace = kubernetes_namespace.web[count.index].metadata[0].name
    labels = {
      "app" = "web"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app" = "web"
      }
    }

    template {
      metadata {
        labels = {
          "app" = "web"
        }
        annotations = {
          "vault.hashicorp.com/agent-inject"                 = "true"
          "vault.hashicorp.com/agent-pre-populate"           = "true"
          "vault.hashicorp.com/role"                         = "web-app"
          "vault.hashicorp.com/agent-inject-secret-config"   = "secret/data/web/app"
          "vault.hashicorp.com/agent-inject-template-config" = <<-EOF
            {{- with secret "secret/data/web/app" -}}
            export APP_ENV="{{ .Data.data.env }}"
            export APP_SECRET="{{ .Data.data.secret }}"
            {{- end }}
          EOF
        }
      }

      spec {
        container {
          name  = "web"
          image = local.web_image

          port {
            name           = "http"
            container_port = 80
          }

          readiness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "128Mi"
            }
          }

          volume_mount {
            name       = "web-content"
            mount_path = "/usr/share/nginx/html"
            read_only  = true
          }

          env_from {
            secret_ref {
              name     = "web-runtime"
              optional = true
            }
          }

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        volume {
          name = "web-content"
          config_map {
            name = kubernetes_config_map.web_content[count.index].metadata[0].name
          }
        }

        security_context {
          fs_group        = 101
          run_as_group    = 101
          run_as_user     = 101
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.vault
  ]
}

resource "kubernetes_service" "web" {
  count = var.enable_web ? 1 : 0

  metadata {
    name      = "web"
    namespace = kubernetes_namespace.web[count.index].metadata[0].name
    labels = {
      "app" = "web"
    }
  }

  spec {
    selector = {
      "app" = "web"
    }

    port {
      name        = "http"
      port        = 80
      target_port = "http"
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "web" {
  count = var.enable_web ? 1 : 0

  metadata {
    name        = "web"
    namespace   = kubernetes_namespace.web[count.index].metadata[0].name
    annotations = local.web_ingress_annotations
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = var.domain_name
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.web[count.index].metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    tls {
      hosts       = [var.domain_name]
      secret_name = "web-tls"
    }
  }

  depends_on = [
    helm_release.ingress_nginx
  ]
}

locals {
  sanitized_project = trim(
    replace(
      replace(
        replace(
          replace(
            replace(
              lower(var.project_name),
              " ",
              "-"
            ),
            "_",
            "-"
          ),
          ".",
          "-"
        ),
        "/",
        "-"
      ),
      ":",
      "-"
    ),
    "-"
  )
  project_slug        = length(local.sanitized_project) > 0 ? local.sanitized_project : "app"
  cluster_name        = "${local.project_slug}-gke"
  network_name        = "${local.project_slug}-vpc"
  subnet_name         = "${local.project_slug}-subnet"
  pod_range_name      = "${local.project_slug}-pods"
  services_range_name = "${local.project_slug}-svc"
  node_pool_name      = "${local.project_slug}-pool"
  router_name         = "${local.project_slug}-router"
  nat_name            = "${local.project_slug}-nat"
  static_ip_name      = "${local.project_slug}-ingress-ip"
  node_sa_id          = substr("${replace(local.project_slug, "-", "")}-gke-nodes", 0, 30)
  node_sa_email       = "${local.node_sa_id}@${var.gcp_project_id}.iam.gserviceaccount.com"
  dns_project_id      = coalesce(var.dns_project_id, var.gcp_project_id)
  labels              = merge({ project = var.project_name }, var.tags)
  node_locations      = length(var.gcp_zones) > 0 ? var.gcp_zones : null
  master_auth_networks = [
    for block in var.gke_master_authorized_networks : {
      cidr  = block.cidr
      label = coalesce(block.label, block.cidr)
    }
  ]
  project_services = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "dns.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ]
}

resource "google_project_service" "required" {
  for_each = toset(local.project_services)

  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_network" "main" {
  name                    = local.network_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  project                 = var.gcp_project_id

  depends_on = [
    google_project_service.required["compute.googleapis.com"]
  ]
}

resource "google_compute_subnetwork" "primary" {
  name                     = local.subnet_name
  ip_cidr_range            = var.vpc_cidr_block
  network                  = google_compute_network.main.id
  region                   = var.gcp_region
  project                  = var.gcp_project_id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = local.pod_range_name
    ip_cidr_range = var.gke_pod_cidr_block
  }

  secondary_ip_range {
    range_name    = local.services_range_name
    ip_cidr_range = var.gke_services_cidr_block
  }

  depends_on = [
    google_project_service.required["compute.googleapis.com"]
  ]
}

resource "google_compute_router" "egress" {
  name    = local.router_name
  region  = var.gcp_region
  network = google_compute_network.main.id
  project = var.gcp_project_id

  depends_on = [
    google_compute_subnetwork.primary,
    google_project_service.required["compute.googleapis.com"]
  ]
}

resource "google_compute_router_nat" "egress" {
  name                               = local.nat_name
  router                             = google_compute_router.egress.name
  region                             = var.gcp_region
  project                            = var.gcp_project_id
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.primary.self_link
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }

  depends_on = [
    google_compute_router.egress,
    google_project_service.required["compute.googleapis.com"]
  ]
}

resource "google_service_account" "gke_nodes" {
  account_id   = local.node_sa_id
  display_name = "GKE nodes ${local.cluster_name}"
  project      = var.gcp_project_id

  depends_on = [
    google_project_service.required["iam.googleapis.com"]
  ]
}

locals {
  node_sa_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer"
  ]
}

resource "google_project_iam_member" "gke_nodes" {
  for_each = toset(local.node_sa_roles)

  project = var.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"

  depends_on = [
    google_project_service.required["iam.googleapis.com"]
  ]
}

resource "google_container_cluster" "main" {
  provider                  = google-beta
  name                      = local.cluster_name
  location                  = var.gcp_region
  project                   = var.gcp_project_id
  network                   = google_compute_network.main.id
  subnetwork                = google_compute_subnetwork.primary.id
  remove_default_node_pool  = true
  initial_node_count        = 1
  default_max_pods_per_node = 110
  enable_shielded_nodes     = true
  deletion_protection       = false

  node_config {
    disk_size_gb = var.gke_node_disk_size_gb
    disk_type    = var.gke_node_disk_type
  }

  release_channel {
    channel = var.gke_release_channel
  }

  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = google_compute_subnetwork.primary.secondary_ip_range[0].range_name
    services_secondary_range_name = google_compute_subnetwork.primary.secondary_ip_range[1].range_name
  }

  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS"
    ]
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "APISERVER",
      "SCHEDULER"
    ]
  }

  private_cluster_config {
    enable_private_endpoint = false
    enable_private_nodes    = true
    master_ipv4_cidr_block  = var.gke_master_ipv4_cidr
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(local.master_auth_networks) > 0 ? [true] : []
    content {
      dynamic "cidr_blocks" {
        for_each = local.master_auth_networks
        content {
          cidr_block   = cidr_blocks.value.cidr
          display_name = cidr_blocks.value.label
        }
      }
    }
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
  }

  depends_on = [
    google_compute_router_nat.egress,
    google_project_iam_member.gke_nodes,
    google_project_service.required["container.googleapis.com"]
  ]

  resource_labels = local.labels
}

resource "google_container_node_pool" "primary" {
  provider           = google-beta
  name               = local.node_pool_name
  cluster            = google_container_cluster.main.id
  location           = var.gcp_region
  project            = var.gcp_project_id
  initial_node_count = var.gke_min_node_count

  node_locations = local.node_locations

  autoscaling {
    min_node_count = var.gke_min_node_count
    max_node_count = var.gke_max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.gke_node_machine_type
    disk_size_gb    = var.gke_node_disk_size_gb
    disk_type       = var.gke_node_disk_type
    preemptible     = false
    service_account = google_service_account.gke_nodes.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    tags = distinct(concat(["gke-node"], var.node_tags))

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  depends_on = [
    google_container_cluster.main,
    google_project_iam_member.gke_nodes
  ]
}

resource "google_compute_address" "ingress" {
  name         = local.static_ip_name
  project      = var.gcp_project_id
  region       = var.gcp_region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"

  depends_on = [
    google_project_service.required["compute.googleapis.com"]
  ]
}

data "google_dns_managed_zone" "primary" {
  name    = var.dns_managed_zone
  project = local.dns_project_id
}
# resource "google_dns_managed_zone" "primary" {
#   name        = var.dns_managed_zone  # tohle je vnitřní název v GCP
#   dns_name    = "${var.domain_name}."      # tvoje doména, MUSÍ mít koncovou tečku
#   project = local.dns_project_id
#   description = "Public zone for machacek.karel.guru"
#   visibility  = "public"
# }

resource "google_dns_record_set" "app" {
  name         = "${var.domain_name}."
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.primary.name
  project      = local.dns_project_id
  rrdatas      = [google_compute_address.ingress.address]

  depends_on = [
    google_project_service.required["dns.googleapis.com"]
  ]
}

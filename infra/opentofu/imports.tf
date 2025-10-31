import {
  to = google_compute_network.main
  id = "projects/${var.gcp_project_id}/global/networks/${local.network_name}"
}

import {
  to = google_compute_subnetwork.primary
  id = "projects/${var.gcp_project_id}/regions/${var.gcp_region}/subnetworks/${local.subnet_name}"
}

import {
  to = google_compute_router.egress
  id = "projects/${var.gcp_project_id}/regions/${var.gcp_region}/routers/${local.router_name}"
}

import {
  to = google_compute_router_nat.egress
  id = "projects/${var.gcp_project_id}/regions/${var.gcp_region}/routers/${local.router_name}/nats/${local.nat_name}"
}

import {
  to = google_service_account.gke_nodes
  id = "projects/${var.gcp_project_id}/serviceAccounts/${local.node_sa_email}"
}

import {
  to = google_compute_address.ingress
  id = "projects/${var.gcp_project_id}/regions/${var.gcp_region}/addresses/${local.static_ip_name}"
}

import {
  to = google_container_cluster.main
  id = "projects/${var.gcp_project_id}/locations/${var.gcp_region}/clusters/${local.cluster_name}"
}

import {
  to = google_container_node_pool.primary
  id = "projects/${var.gcp_project_id}/locations/${var.gcp_region}/clusters/${local.cluster_name}/nodePools/${local.node_pool_name}"
}

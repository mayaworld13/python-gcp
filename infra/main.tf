# Artifact Registry repo
resource "google_artifact_registry_repository" "docker_repo" {
  provider      = google
  location      = var.region
  repository_id = var.artifact_repo
  description   = "Artifact Registry for flaskapp images"
  format        = "DOCKER"
}

# Grant Cloud Build SA permissions to push images and deploy to cluster
# Cloud Build uses: PROJECT_NUMBER@cloudbuild.gserviceaccount.com
data "google_project" "project" {
  project_id = var.project_id
}

data "google_service_account" "cloudbuild_sa" {
  account_id = "${data.google_project.project.number}-compute@developer.gserviceaccount.com"
  project    = var.project_id
}



output "project_number" {
  value = data.google_project.project.number
}


resource "google_project_iam_member" "cloudbuild_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudbuild_gke_admin" {
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}


resource "google_cloudbuildv2_connection" "my-connection" {
  location = var.region
  name     = var.connection_name

  github_config {
    app_installation_id = var.app_installation_id
    authorizer_credential {
      oauth_token_secret_version = var.oauth_token_secret_version
    }
  }
}

resource "google_cloudbuildv2_repository" "my-repository" {
  name              = var.google_cloudbuildv2_repository
  parent_connection = google_cloudbuildv2_connection.my-connection.id
  remote_uri        = var.remote_uri
}

resource "google_cloudbuild_trigger" "repo-trigger" {
  service_account = "projects/${var.project_id}/serviceAccounts/${data.google_project.project.number}-compute@developer.gserviceaccount.com"
  name            = var.trigger_name
  location        = var.region

  repository_event_config {
    repository = google_cloudbuildv2_repository.my-repository.id
    push {
      branch = "^main$"
    }
  }
  filename = "cloudbuild1.yaml"
  ignored_files = [
    "flaskapp/values.yaml",
    "deployment.yaml",
    "README.MD",
    "infra/*"
  ]
  
  include_build_logs = "INCLUDE_BUILD_LOGS_WITH_STATUS"

}


resource "google_container_cluster" "autopilot_cluster" {
  name     = var.gke-cluster_name
  location = var.region

  enable_autopilot = true

  network    = "default"
  subnetwork = "default"

  deletion_protection = false
}

# Cluster Authentication
# ────────────────────────────────
data "google_client_config" "default" {}

data "google_container_cluster" "primary" {
  name     = google_container_cluster.autopilot_cluster.name
  location = var.region
}

provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.primary.endpoint}"
  cluster_ca_certificate = base64decode(data.google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}

provider "helm" {
  kubernetes {
    host                   = "https://${data.google_container_cluster.primary.endpoint}"
    cluster_ca_certificate = base64decode(data.google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
    token                  = data.google_client_config.default.access_token
  }
}

provider "kubectl" {
  host                   = "https://${data.google_container_cluster.primary.endpoint}"
  cluster_ca_certificate = base64decode(data.google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
  load_config_file       = false
}


# ────────────────────────────────
# Ingress Controller via Helm
# ────────────────────────────────
resource "helm_release" "nginx_ingress" {
  name             = "nginx-ingress"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  depends_on = [google_container_cluster.autopilot_cluster]
}

# ArgoCD Installation
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true

  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "server.service.port"
    value = "80"
  }

  depends_on = [
    google_container_cluster.autopilot_cluster,
    helm_release.nginx_ingress
  ]
}


# ArgoCD Admin Password Output
# ────────────────────────────────
data "kubernetes_secret" "argocd_admin_secret" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = "argocd"
  }
  depends_on = [helm_release.argocd]
}

output "argocd_admin_password" {
  value     = data.kubernetes_secret.argocd_admin_secret.data["password"]
  sensitive = true
}

# ────────────────────────────────
# ArgoCD External LoadBalancer IP
# ────────────────────────────────
output "argocd_server_ip" {
  description = "External IP of ArgoCD Server"
  value       = data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].ip
}

data "kubernetes_service" "argocd_server" {
  metadata {
    name      = "argocd-server"
    namespace = "argocd"
  }
  depends_on = [helm_release.argocd]
}


resource "kubectl_manifest" "flaskapp_argocd_app" {
  yaml_body = file("${path.module}/argocd-app.yaml")
  depends_on = [
    helm_release.argocd
  ]
}
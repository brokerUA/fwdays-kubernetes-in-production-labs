terraform {
  required_version = "= 1.16.5"
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "= 0.11.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "= 2.33.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "= 2.17.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "= 2.5.2"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "= 1.19.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "kind" {}

resource "kind_cluster" "this" {
  name           = var.cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    # Explicitly define one control-plane and three worker nodes
    node {
      role = "control-plane"
    }
    node {
      role = "worker"
    }
    node {
      role = "worker"
    }
    node {
      role = "worker"
    }
  }
}

# Write the admin kubeconfig to a local file so that the kubernetes, helm, and
# kubectl providers can read it by path. This makes `terraform destroy` safe
# even when the cluster API is unreachable: the file already exists on disk and
# the providers don't need a live endpoint to initialize.
resource "local_file" "admin_kubeconfig" {
  filename        = "${path.module}/admin.kubeconfig"
  content         = kind_cluster.this.kubeconfig
  file_permission = "0600"
}

provider "kubernetes" {
  config_path = local_file.admin_kubeconfig.filename
}

provider "helm" {
  kubernetes {
    config_path = local_file.admin_kubeconfig.filename
  }
}

provider "kubectl" {
  config_path      = local_file.admin_kubeconfig.filename
  load_config_file = true
}

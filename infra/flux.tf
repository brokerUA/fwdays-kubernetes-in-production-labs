# ==========================================
# Bootstrap Flux Operator & Flux Instance
# ==========================================

# 1. Flux Operator
resource "helm_release" "flux_operator" {
  depends_on       = [kind_cluster.this]
  name             = "flux-operator"
  namespace        = "flux-system"
  repository       = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart            = "flux-operator"
  version          = var.flux_operator_version
  create_namespace = true
  wait             = true
  timeout          = 300
}

# 2. Cluster ConfigMap in flux-system for dynamic OCI variable substitution
resource "kubernetes_config_map" "cluster_config" {
  depends_on = [helm_release.flux_operator]

  metadata {
    name      = "cluster-config"
    namespace = "flux-system"
  }

  data = {
    OCI_REGISTRY_OWNER = var.ghcr_owner
  }
}

# 3. Flux Instance managed by Flux Operator (OCI Platform Root Reconciliation)
resource "helm_release" "flux_instance" {
  depends_on       = [helm_release.flux_operator, kubernetes_config_map.cluster_config]
  name             = "flux-instance"
  namespace        = "flux-system"
  repository       = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart            = "flux-instance"
  version          = var.flux_instance_version
  create_namespace = true
  wait             = true
  timeout          = 300

  set {
    name  = "instance.distribution.version"
    value = "2.x"
  }

  set {
    name  = "instance.sync.kind"
    value = "OCIRepository"
  }

  set {
    name  = "instance.sync.url"
    value = "oci://ghcr.io/${var.ghcr_owner}/${var.platform_oci_repository}"
  }

  set {
    name  = "instance.sync.ref"
    value = var.platform_oci_tag
  }

  set {
    name  = "instance.sync.path"
    value = "."
  }
}

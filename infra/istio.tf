# ==========================================
# Istio Service Mesh Core Infrastructure
# ==========================================

# 1. Istio Base (CRDs, ClusterRoles, and Base Webhook Configurations)
resource "helm_release" "istio_base" {
  depends_on       = [kind_cluster.this]
  name             = "istio-base"
  namespace        = "istio-system"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  version          = var.istio_version
  create_namespace = true
  wait             = true
  timeout          = 300
}

# 2. Istio Control Plane (istiod with Sidecar Injector Webhook)
resource "helm_release" "istiod" {
  depends_on       = [helm_release.istio_base]
  name             = "istiod"
  namespace        = "istio-system"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "istiod"
  version          = var.istio_version
  create_namespace = false
  wait             = true
  timeout          = 300

  set {
    name  = "meshConfig.accessLogFile"
    value = "/dev/stdout"
  }

  set {
    name  = "meshConfig.enableAutoMtls"
    value = "true"
  }

  set {
    name  = "pilot.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "pilot.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "sidecarInjectorWebhook.reinvocationPolicy"
    value = "IfNeeded"
  }
}

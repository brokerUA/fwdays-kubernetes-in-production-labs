# ==========================================
# KinD Multi-node Cluster with IPVS & CEL
# ==========================================

resource "kind_cluster" "this" {
  name           = var.cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    feature_gates = {
      "MutatingAdmissionPolicy" = "true"
    }

    runtime_config = {
      "admissionregistration.k8s.io/v1alpha1" = "true"
      "admissionregistration.k8s.io/v1beta1"  = "true"
    }

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

    networking {
      kube_proxy_mode = "ipvs"
    }
  }
}

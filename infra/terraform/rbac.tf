# RBAC Roles
# rw-role: full read-write access in student01, student02, student03
# ro-role: read-only access in student01 and default

locals {
  rw_verbs = ["get", "list", "watch", "create", "update", "patch", "delete"]
  ro_verbs = ["get", "list", "watch"]

  common_rules = [
    {
      api_groups = [""]
      resources  = ["pods", "services", "configmaps", "secrets"]
    },
    {
      api_groups = ["apps"]
      resources  = ["deployments"]
    },
  ]
}

# ── rw-role in student01 ────────────────────────────────────────────────────

resource "kubernetes_role" "rw_student01" {
  metadata {
    name      = "rw-role"
    namespace = kubernetes_namespace.student01.metadata[0].name
  }

  dynamic "rule" {
    for_each = local.common_rules
    content {
      api_groups = rule.value.api_groups
      resources  = rule.value.resources
      verbs      = local.rw_verbs
    }
  }

  depends_on = [kubernetes_namespace.student01]
}

# ── rw-role in student02 ────────────────────────────────────────────────────

resource "kubernetes_role" "rw_student02" {
  metadata {
    name      = "rw-role"
    namespace = kubernetes_namespace.student02.metadata[0].name
  }

  dynamic "rule" {
    for_each = local.common_rules
    content {
      api_groups = rule.value.api_groups
      resources  = rule.value.resources
      verbs      = local.rw_verbs
    }
  }

  depends_on = [kubernetes_namespace.student02]
}

# ── rw-role in student03 ────────────────────────────────────────────────────

resource "kubernetes_role" "rw_student03" {
  metadata {
    name      = "rw-role"
    namespace = kubernetes_namespace.student03.metadata[0].name
  }

  dynamic "rule" {
    for_each = local.common_rules
    content {
      api_groups = rule.value.api_groups
      resources  = rule.value.resources
      verbs      = local.rw_verbs
    }
  }

  depends_on = [kubernetes_namespace.student03]
}

# ── ro-role in student01 ────────────────────────────────────────────────────

resource "kubernetes_role" "ro_student01" {
  metadata {
    name      = "ro-role"
    namespace = kubernetes_namespace.student01.metadata[0].name
  }

  dynamic "rule" {
    for_each = local.common_rules
    content {
      api_groups = rule.value.api_groups
      resources  = rule.value.resources
      verbs      = local.ro_verbs
    }
  }

  depends_on = [kubernetes_namespace.student01]
}

# ── ro-role in default (built-in namespace, no depends_on needed) ───────────

resource "kubernetes_role" "ro_default" {
  metadata {
    name      = "ro-role"
    namespace = "default"
  }

  dynamic "rule" {
    for_each = local.common_rules
    content {
      api_groups = rule.value.api_groups
      resources  = rule.value.resources
      verbs      = local.ro_verbs
    }
  }
}

# ── Mentor RoleBindings ─────────────────────────────────────────────────────
# Mentor SA bound to rw-role in each student namespace (no ClusterRoleBindings)

resource "kubernetes_role_binding" "mentor_rw_student01" {
  metadata {
    name      = "mentor-rw"
    namespace = kubernetes_namespace.student01.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.rw_student01.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.mentor.metadata[0].name
    namespace = kubernetes_namespace.mentor.metadata[0].name
  }
}

resource "kubernetes_role_binding" "mentor_rw_student02" {
  metadata {
    name      = "mentor-rw"
    namespace = kubernetes_namespace.student02.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.rw_student02.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.mentor.metadata[0].name
    namespace = kubernetes_namespace.mentor.metadata[0].name
  }
}

resource "kubernetes_role_binding" "mentor_rw_student03" {
  metadata {
    name      = "mentor-rw"
    namespace = kubernetes_namespace.student03.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.rw_student03.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.mentor.metadata[0].name
    namespace = kubernetes_namespace.mentor.metadata[0].name
  }
}

# ── Student RoleBindings ────────────────────────────────────────────────────

resource "kubernetes_role_binding" "student01_rw_student01" {
  metadata {
    name      = "student01-rw"
    namespace = kubernetes_namespace.student01.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.rw_student01.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.student01.metadata[0].name
    namespace = kubernetes_namespace.student01.metadata[0].name
  }
}

resource "kubernetes_role_binding" "student02_ro_student01" {
  metadata {
    name      = "student02-ro"
    namespace = kubernetes_namespace.student01.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.ro_student01.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.student02.metadata[0].name
    namespace = kubernetes_namespace.student02.metadata[0].name
  }
}

resource "kubernetes_role_binding" "student02_ro_default" {
  metadata {
    name      = "student02-ro"
    namespace = "default"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.ro_default.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.student02.metadata[0].name
    namespace = kubernetes_namespace.student02.metadata[0].name
  }
}

resource "kubernetes_role_binding" "student03_rw_student03" {
  metadata {
    name      = "student03-rw"
    namespace = kubernetes_namespace.student03.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.rw_student03.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.student03.metadata[0].name
    namespace = kubernetes_namespace.student03.metadata[0].name
  }
}

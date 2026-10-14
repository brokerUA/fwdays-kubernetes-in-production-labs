resource "kubernetes_service_account" "mentor" {
  metadata {
    name      = "mentor"
    namespace = kubernetes_namespace.mentor.metadata[0].name
  }
}

resource "kubernetes_secret" "mentor_token" {
  metadata {
    name      = "mentor-token"
    namespace = kubernetes_namespace.mentor.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.mentor.metadata[0].name
    }
  }
  type = "kubernetes.io/service-account-token"
}

resource "kubernetes_service_account" "student01" {
  metadata {
    name      = "student01"
    namespace = kubernetes_namespace.student01.metadata[0].name
  }
}

resource "kubernetes_secret" "student01_token" {
  metadata {
    name      = "student01-token"
    namespace = kubernetes_namespace.student01.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.student01.metadata[0].name
    }
  }
  type = "kubernetes.io/service-account-token"
}

resource "kubernetes_service_account" "student02" {
  metadata {
    name      = "student02"
    namespace = kubernetes_namespace.student02.metadata[0].name
  }
}

resource "kubernetes_secret" "student02_token" {
  metadata {
    name      = "student02-token"
    namespace = kubernetes_namespace.student02.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.student02.metadata[0].name
    }
  }
  type = "kubernetes.io/service-account-token"
}

resource "kubernetes_service_account" "student03" {
  metadata {
    name      = "student03"
    namespace = kubernetes_namespace.student03.metadata[0].name
  }
}

resource "kubernetes_secret" "student03_token" {
  metadata {
    name      = "student03-token"
    namespace = kubernetes_namespace.student03.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.student03.metadata[0].name
    }
  }
  type = "kubernetes.io/service-account-token"
}

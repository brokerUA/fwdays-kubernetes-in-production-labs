resource "kubernetes_namespace" "mentor" {
  metadata {
    name = "mentor"
  }
}

resource "kubernetes_namespace" "student01" {
  metadata {
    name = "student01"
  }
}

resource "kubernetes_namespace" "student02" {
  metadata {
    name = "student02"
  }
}

resource "kubernetes_namespace" "student03" {
  metadata {
    name = "student03"
  }
}

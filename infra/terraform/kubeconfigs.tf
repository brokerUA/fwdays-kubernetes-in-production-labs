resource "local_file" "kubeconfig_mentor" {
  filename = "${var.kubeconfig_dir}/kubeconfig-mentor.yaml"
  content = templatefile("${path.module}/templates/kubeconfig.tpl", {
    ca_cert           = kind_cluster.this.cluster_ca_certificate
    server            = kind_cluster.this.endpoint
    cluster_name      = var.cluster_name
    default_namespace = "mentor"
    user_name         = "mentor"
    token             = kubernetes_secret.mentor_token.data.token
  })

  depends_on = [kubernetes_secret.mentor_token]
}

resource "local_file" "kubeconfig_student01" {
  filename = "${var.kubeconfig_dir}/kubeconfig-student01.yaml"
  content = templatefile("${path.module}/templates/kubeconfig.tpl", {
    ca_cert           = kind_cluster.this.cluster_ca_certificate
    server            = kind_cluster.this.endpoint
    cluster_name      = var.cluster_name
    default_namespace = "student01"
    user_name         = "student01"
    token             = kubernetes_secret.student01_token.data.token
  })

  depends_on = [kubernetes_secret.student01_token]
}

resource "local_file" "kubeconfig_student02" {
  filename = "${var.kubeconfig_dir}/kubeconfig-student02.yaml"
  content = templatefile("${path.module}/templates/kubeconfig.tpl", {
    ca_cert           = kind_cluster.this.cluster_ca_certificate
    server            = kind_cluster.this.endpoint
    cluster_name      = var.cluster_name
    default_namespace = "student02"
    user_name         = "student02"
    token             = kubernetes_secret.student02_token.data.token
  })

  depends_on = [kubernetes_secret.student02_token]
}

resource "local_file" "kubeconfig_student03" {
  filename = "${var.kubeconfig_dir}/kubeconfig-student03.yaml"
  content = templatefile("${path.module}/templates/kubeconfig.tpl", {
    ca_cert           = kind_cluster.this.cluster_ca_certificate
    server            = kind_cluster.this.endpoint
    cluster_name      = var.cluster_name
    default_namespace = "student03"
    user_name         = "student03"
    token             = kubernetes_secret.student03_token.data.token
  })

  depends_on = [kubernetes_secret.student03_token]
}

output "cluster_endpoint" {
  value = kind_cluster.this.endpoint
}

output "kubeconfig_paths" {
  value = {
    mentor    = local_file.kubeconfig_mentor.filename
    student01 = local_file.kubeconfig_student01.filename
    student02 = local_file.kubeconfig_student02.filename
    student03 = local_file.kubeconfig_student03.filename
  }
}

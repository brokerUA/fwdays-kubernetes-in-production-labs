output "cluster_name" {
  description = "Name of the provisioned KinD cluster"
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = kind_cluster.this.endpoint
}

output "admin_kubeconfig_path" {
  description = "Path to the administrative kubeconfig file"
  value       = kind_cluster.this.kubeconfig_path
}

output "kubeconfig_path" {
  description = "Path to the administrative kubeconfig file"
  value       = kind_cluster.this.kubeconfig_path
}

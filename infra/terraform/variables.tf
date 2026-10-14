variable "cluster_name" {
  description = "Name of the kind cluster"
  type        = string
  default     = "k8s-in-production"
}

variable "kubeconfig_dir" {
  description = "Directory where kubeconfig files will be written"
  type        = string
  default     = "../../"
}

variable "kyverno_chart_version" {
  description = "Kyverno Helm chart version"
  type        = string
  default     = "3.9.1"
}

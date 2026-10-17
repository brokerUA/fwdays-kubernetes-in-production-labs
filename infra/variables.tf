variable "cluster_name" {
  description = "Name of the KinD cluster"
  type        = string
  default     = "k8s-in-production"
}

variable "ghcr_owner" {
  description = "GHCR repository owner / organization for OCI charts and platform artifacts"
  type        = string
  default     = "brokerua"
}

variable "flux_operator_version" {
  description = "Flux Operator Helm chart version"
  type        = string
  default     = "0.61.0"
}

variable "flux_instance_version" {
  description = "Flux Instance Helm chart version"
  type        = string
  default     = "0.61.0"
}

variable "platform_oci_repository" {
  description = "OCI repository name for the platform root manifests artifact"
  type        = string
  default     = "platform-flux"
}

variable "platform_oci_tag" {
  description = "OCI artifact tag for the platform root manifests"
  type        = string
  default     = "latest"
}

variable "istio_version" {
  description = "Istio Helm chart version (base and istiod control plane)"
  type        = string
  default     = "1.30.6"
}

variable "istio_operator_version" {
  description = "Istio Operator component version reference"
  type        = string
  default     = "1.30.6"
}

variable "vm_stack_chart_version" {
  description = "VictoriaMetrics K8s Stack Helm chart version"
  type        = string
  default     = "0.96.0"
}

# ==========================================
# VictoriaMetrics Observability Stack
# ==========================================

resource "helm_release" "victoria_metrics_stack" {
  depends_on       = [kind_cluster.this]
  name             = "victoria-metrics-k8s-stack"
  namespace        = "monitoring"
  repository       = "https://victoriametrics.github.io/helm-charts/"
  chart            = "victoria-metrics-k8s-stack"
  version          = var.vm_stack_chart_version
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [
    yamlencode({
      victoria-metrics-operator = {
        crds = {
          cleanup = {
            enabled = false
          }
        }
      }
      vmsingle = {
        enabled = true
        spec = {
          retentionPeriod = "7d"
          resources = {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }
      }
      vmagent = {
        enabled = true
        spec = {
          resources = {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }
        }
      }
      vmalert = {
        enabled = true
        spec = {
          resources = {
            requests = {
              cpu    = "20m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }
        }
      }
      grafana = {
        enabled = true
        sidecar = {
          dashboards = {
            enabled         = true
            label           = "grafana_dashboard"
            labelValue      = "1"
            searchNamespace = "ALL"
          }
          datasources = {
            enabled = true
          }
        }
        resources = {
          requests = {
            cpu    = "50m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }
      kubeApiServer = {
        enabled = true
      }
      kube-state-metrics = {
        enabled = true
      }
      prometheus-node-exporter = {
        enabled = true
      }
    })
  ]
}

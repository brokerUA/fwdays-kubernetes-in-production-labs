#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Module 05 Observability & Security Auditing Verification Script
# Verifies VictoriaMetrics K8s Stack, Grafana Dashboards, Metrics Ingestion,
# and CEL Admission Audit Alerts (ReadOnly RootFS)
# ==============================================================================

# Automatically locate admin kubeconfig if KUBECONFIG is not explicitly set
if [[ -z "${KUBECONFIG:-}" ]]; then
  if [[ -f "infra/k8s-in-production-config" ]]; then
    export KUBECONFIG="$(pwd)/infra/k8s-in-production-config"
  elif [[ -f "../infra/k8s-in-production-config" ]]; then
    export KUBECONFIG="$(pwd)/../infra/k8s-in-production-config"
  elif [[ -f "infra/admin.kubeconfig" ]]; then
    export KUBECONFIG="$(pwd)/infra/admin.kubeconfig"
  elif [[ -f "../infra/admin.kubeconfig" ]]; then
    export KUBECONFIG="$(pwd)/../infra/admin.kubeconfig"
  fi
fi

PASS=0
FAIL=0

cleanup() {
  kubectl delete pod test-readonly-audit-violation -n student01 --ignore-not-found=true 2>/dev/null || true
}
trap cleanup EXIT

log_pass() {
  echo -e "\033[0;32m[PASS]\033[0m $1"
  ((PASS++)) || true
}

log_fail() {
  echo -e "\033[0;31m[FAIL]\033[0m $1"
  ((FAIL++)) || true
}

# ------------------------------------------------------------------------------
# 1. Cluster & Monitoring Namespace Checks
# ------------------------------------------------------------------------------
echo "=== Phase 1: KinD Cluster & Monitoring Namespace Checks ==="
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$NODE_COUNT" -gt 0 ]]; then
  log_pass "KinD cluster is accessible ($NODE_COUNT node(s) detected)"
else
  log_fail "No Kubernetes nodes detected or cluster unreachable"
fi

if kubectl get ns monitoring >/dev/null 2>&1; then
  log_pass "Namespace 'monitoring' exists"
else
  log_fail "Namespace 'monitoring' not found"
fi

# ------------------------------------------------------------------------------
# 2. VictoriaMetrics Observability Stack Components Health
# ------------------------------------------------------------------------------
echo ""
echo "=== Phase 2: VictoriaMetrics Stack Health Checks ==="

check_pod_ready() {
  local label="$1"
  local name="$2"
  local ready_status
  ready_status=$(kubectl get pods -n monitoring -l "$label" -o jsonpath='{.items[0].status.containerStatuses[*].ready}' 2>/dev/null || true)
  if [[ "$ready_status" =~ "true" ]]; then
    log_pass "Component '$name' is running and Ready in 'monitoring'"
  else
    log_fail "Component '$name' is not ready in 'monitoring' (status: '${ready_status}')"
  fi
}

check_pod_ready "app.kubernetes.io/name=victoria-metrics-operator" "VictoriaMetrics Operator"
check_pod_ready "app.kubernetes.io/name=vmsingle" "VictoriaMetrics Single (VMSingle TSDB)"
check_pod_ready "app.kubernetes.io/name=vmagent" "VictoriaMetrics Agent (VMAgent Scraper)"
check_pod_ready "app.kubernetes.io/name=vmalert" "VictoriaMetrics Alert (VMAlert Engine)"
check_pod_ready "app.kubernetes.io/name=grafana" "Grafana Server & Dashboard Sidecar"
check_pod_ready "app.kubernetes.io/name=kube-state-metrics" "kube-state-metrics"

NODE_EXPORTER_COUNT=$(kubectl get pods -n monitoring -l "app.kubernetes.io/name=prometheus-node-exporter" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$NODE_EXPORTER_COUNT" -ge "$NODE_COUNT" ]]; then
  log_pass "Node Exporter DaemonSet is active across all $NODE_COUNT nodes"
else
  log_fail "Node Exporter DaemonSet running pods ($NODE_EXPORTER_COUNT) less than node count ($NODE_COUNT)"
fi

# ------------------------------------------------------------------------------
# 3. Grafana Dashboard Sidecar Discovery & API Verification
# ------------------------------------------------------------------------------
echo ""
echo "=== Phase 3: Grafana Dashboard Discovery & API Checks ==="

GF_PASS=$(kubectl get secret --namespace monitoring victoria-metrics-k8s-stack-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 --decode || true)
if [[ -n "$GF_PASS" ]]; then
  log_pass "Retrieved Grafana administrator credentials"
else
  log_fail "Failed to retrieve Grafana admin password from secret"
fi

SEARCH_RESULTS=$(kubectl exec -n monitoring deploy/victoria-metrics-k8s-stack-grafana -c grafana-sc-dashboard -- wget -qO- --header="Authorization: Basic $(echo -n admin:$GF_PASS | base64)" http://localhost:3000/api/search 2>/dev/null || true)

if [[ "$SEARCH_RESULTS" =~ "student-node-utilization" ]]; then
  log_pass "Grafana discovered dashboard: 'Student Namespaces - Node Utilization' (uid: student-node-utilization)"
else
  log_fail "Grafana missing dashboard: 'Student Namespaces - Node Utilization'"
fi

if [[ "$SEARCH_RESULTS" =~ "readonly-rootfs-audit" ]]; then
  log_pass "Grafana discovered dashboard: 'Security Policies - ReadOnly RootFS Audit' (uid: readonly-rootfs-audit)"
else
  log_fail "Grafana missing dashboard: 'Security Policies - ReadOnly RootFS Audit'"
fi

# ------------------------------------------------------------------------------
# 4. Metric Scraping & Student Namespace Utilization Ingestion
# ------------------------------------------------------------------------------
echo ""
echo "=== Phase 4: MetricsQL Ingestion & Student Namespace Checks ==="

VMSINGLE_URL="http://vmsingle-victoria-metrics-k8s-stack.monitoring.svc.cluster.local:8428"

KSM_METRICS=$(kubectl exec -n monitoring deploy/victoria-metrics-k8s-stack-grafana -c grafana-sc-dashboard -- wget -qO- "${VMSINGLE_URL}/api/v1/query?query=count(kube_pod_info%7Bnamespace%3D~%22student.*%22%7D)" 2>/dev/null || true)
if [[ "$KSM_METRICS" =~ "result\":[" && ! "$KSM_METRICS" =~ "result\":[]" ]]; then
  log_pass "VMSingle successfully ingests kube-state-metrics for student workloads"
else
  log_fail "VMSingle query for student pod metrics returned empty or error: ${KSM_METRICS}"
fi

NODE_METRICS=$(kubectl exec -n monitoring deploy/victoria-metrics-k8s-stack-grafana -c grafana-sc-dashboard -- wget -qO- "${VMSINGLE_URL}/api/v1/query?query=sum(rate(node_cpu_seconds_total%5B5m%5D))" 2>/dev/null || true)
if [[ "$NODE_METRICS" =~ "result\":[" && ! "$NODE_METRICS" =~ "result\":[]" ]]; then
  log_pass "VMSingle successfully ingests node-exporter CPU metrics across KinD nodes"
else
  log_fail "VMSingle query for node CPU metrics returned empty or error: ${NODE_METRICS}"
fi

# ------------------------------------------------------------------------------
# 5. Security Policy CEL Admission Audit & VMAlert Evaluation
# ------------------------------------------------------------------------------
echo ""
echo "=== Phase 5: Security Policy CEL Admission Audit & Alert Checks ==="

if kubectl get vmrule readonly-rootfs-audit-alerts -n monitoring >/dev/null 2>&1; then
  log_pass "VMRule 'readonly-rootfs-audit-alerts' is active and managed by operator"
else
  log_fail "VMRule 'readonly-rootfs-audit-alerts' not found in monitoring namespace"
fi

# Deploy non-compliant pod violating require-readonly-rootfs
echo "Deploying test pod with writable root filesystem into 'student01'..."
kubectl delete pod test-readonly-audit-violation -n student01 --ignore-not-found=true >/dev/null 2>&1 || true

cat <<EOF | kubectl apply -n student01 -f - >/dev/null 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: test-readonly-audit-violation
  labels:
    person: student
spec:
  containers:
    - name: test-app
      image: alpine:latest
      command: ["sh", "-c", "sleep 3600"]
      securityContext:
        readOnlyRootFilesystem: false
EOF

# Give VMAgent and VMAlert a brief moment to scrape and evaluate
echo "Waiting for admission audit metric scrape and alert evaluation..."
ALERT_FIRED=false
for i in {1..12}; do
  ALERTS_RESP=$(kubectl exec -n monitoring deploy/victoria-metrics-k8s-stack-grafana -c grafana-sc-dashboard -- wget -qO- "http://vmalert-victoria-metrics-k8s-stack.monitoring.svc.cluster.local:8080/api/v1/alerts" 2>/dev/null || true)
  if [[ "$ALERTS_RESP" =~ "ReadOnlyRootFilesystemAuditViolation" && "$ALERTS_RESP" =~ "firing" ]]; then
    ALERT_FIRED=true
    break
  fi
  sleep 5
done

if [[ "$ALERT_FIRED" == "true" ]]; then
  log_pass "VMAlert successfully triggered 'ReadOnlyRootFilesystemAuditViolation' in state FIRING"
else
  log_fail "VMAlert did not trigger 'ReadOnlyRootFilesystemAuditViolation' within timeout"
fi

# Clean up violation pod
kubectl delete pod test-readonly-audit-violation -n student01 --grace-period=0 --force >/dev/null 2>&1 || true

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo ""
echo "=============================================================================="
echo "Verification Summary: ${PASS} Passed, ${FAIL} Failed"
echo "=============================================================================="

if [[ "$FAIL" -eq 0 ]]; then
  echo -e "\033[0;32mAll Module 05 verification checks passed successfully!\033[0m"
  exit 0
else
  echo -e "\033[0;31mModule 05 verification failed with ${FAIL} error(s).\033[0m"
  exit 1
fi

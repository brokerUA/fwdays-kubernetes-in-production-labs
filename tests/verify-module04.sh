#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Module 04 Service Mesh Verification Script
# Verifies KinD, Istio Control Plane, CEL Mutating Admission Policy, and Sidecar Injection
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
  kubectl delete pod test-istio-student01 -n student01 --ignore-not-found=true 2>/dev/null || true
  kubectl delete pod test-istio-mentor    -n mentor    --ignore-not-found=true 2>/dev/null || true
  kubectl delete pod test-istio-other     -n default   --ignore-not-found=true 2>/dev/null || true
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
# 1. Cluster & Node Inspection (KinD)
# ------------------------------------------------------------------------------
echo "=== Phase 1: KinD Cluster & Node Checks ==="
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$NODE_COUNT" -gt 0 ]]; then
  log_pass "KinD cluster is accessible ($NODE_COUNT node(s) detected)"
else
  log_fail "No Kubernetes nodes detected or cluster unreachable"
fi

# ------------------------------------------------------------------------------
# 2. Istio Control Plane Health Checks
# ------------------------------------------------------------------------------
echo ""
echo "=== Phase 2: Istio Control Plane Health Checks ==="

# Check istio-system namespace
if kubectl get ns istio-system >/dev/null 2>&1; then
  log_pass "Namespace 'istio-system' exists"
else
  log_fail "Namespace 'istio-system' not found"
fi

# Check istiod running
ISTIOD_READY=$(kubectl get pods -n istio-system -l app=istiod -o jsonpath='{.items[*].status.containerStatuses[*].ready}' 2>/dev/null || true)
if [[ "$ISTIOD_READY" =~ "true" ]]; then
  log_pass "Istio control plane ('istiod') is running and Ready in 'istio-system'"
else
  log_fail "Istio control plane ('istiod') is not running or not Ready in 'istio-system' (status: '${ISTIOD_READY}')"
fi

# Check Istio MutatingWebhookConfiguration
if kubectl get mutatingwebhookconfiguration istio-sidecar-injector >/dev/null 2>&1; then
  log_pass "Istio MutatingWebhookConfiguration 'istio-sidecar-injector' is active"
else
  log_fail "Istio MutatingWebhookConfiguration 'istio-sidecar-injector' not found"
fi

# ------------------------------------------------------------------------------
# 3. Native CEL MutatingAdmissionPolicy Checks
# ------------------------------------------------------------------------------
echo ""
echo "=== Phase 3: Native CEL Admission Policy Checks ==="

if kubectl get mutatingadmissionpolicy person-label-and-sidecar >/dev/null 2>&1; then
  log_pass "CEL MutatingAdmissionPolicy 'person-label-and-sidecar' is defined"
else
  log_fail "CEL MutatingAdmissionPolicy 'person-label-and-sidecar' not found"
fi

if kubectl get mutatingadmissionpolicybinding person-label-and-sidecar >/dev/null 2>&1; then
  log_pass "CEL MutatingAdmissionPolicyBinding 'person-label-and-sidecar' is defined"
else
  log_fail "CEL MutatingAdmissionPolicyBinding 'person-label-and-sidecar' not found"
fi

# The two legacy policies depended on admission ordering and must be gone
for legacy in add-person-label inject-istio-sidecar; do
  if kubectl get mutatingadmissionpolicy "$legacy" >/dev/null 2>&1; then
    log_fail "Legacy order-dependent MutatingAdmissionPolicy '$legacy' still exists"
  else
    log_pass "Legacy MutatingAdmissionPolicy '$legacy' is removed"
  fi
done

# ------------------------------------------------------------------------------
# 4. Automated Sidecar Injection for Student Workload
# ------------------------------------------------------------------------------
echo ""
echo "=== Phase 4: Automated Sidecar Injection for Student Workload ==="

# Create test pod in student01 namespace
kubectl delete pod test-istio-student01 -n student01 --ignore-not-found=true >/dev/null 2>&1 || true

cat <<EOF | kubectl apply -n student01 -f - >/dev/null 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: test-istio-student01
spec:
  containers:
    - name: test-app
      image: alpine:latest
      command: ["sh", "-c", "sleep 3600"]
      securityContext:
        readOnlyRootFilesystem: true
EOF

# Verify student person label was applied
STUDENT_LABEL=$(kubectl get pod test-istio-student01 -n student01 -o jsonpath='{.metadata.labels.person}' 2>/dev/null || true)
if [[ "$STUDENT_LABEL" == "student" ]]; then
  log_pass "Pod in student01 automatically received label person=student"
else
  log_fail "Pod in student01 missing person=student label (got: '${STUDENT_LABEL}')"
fi

# Verify sidecar injection label was mutated by CEL MAP
INJECT_LABEL=$(kubectl get pod test-istio-student01 -n student01 -o jsonpath='{.metadata.labels.sidecar\.istio\.io/inject}' 2>/dev/null || true)
if [[ "$INJECT_LABEL" == "true" ]]; then
  log_pass "CEL MutatingAdmissionPolicy mutated sidecar.istio.io/inject=true onto student pod"
else
  log_fail "Student pod missing sidecar.istio.io/inject=true (got: '${INJECT_LABEL}')"
fi

# Verify istio-proxy sidecar container injection (standard or native sidecar in initContainers)
ALL_CONTAINERS=$(kubectl get pod test-istio-student01 -n student01 -o jsonpath='{.spec.initContainers[*].name} {.spec.containers[*].name}' 2>/dev/null || true)
if [[ "$ALL_CONTAINERS" =~ "istio-proxy" ]]; then
  log_pass "Istio proxy sidecar container ('istio-proxy') successfully injected into student pod"
else
  log_fail "Student pod does not contain 'istio-proxy' container (containers: '${ALL_CONTAINERS}')"
fi

# ------------------------------------------------------------------------------
# 5. Non-Student Pod Exemption Check
# ------------------------------------------------------------------------------
echo ""
echo "=== Phase 5: Non-Student Pod Exemption Check ==="

kubectl delete pod test-istio-mentor -n mentor --ignore-not-found=true >/dev/null 2>&1 || true

cat <<EOF | kubectl apply -n mentor -f - >/dev/null 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: test-istio-mentor
spec:
  containers:
    - name: test-app
      image: alpine:latest
      command: ["sh", "-c", "sleep 3600"]
      securityContext:
        readOnlyRootFilesystem: true
EOF

MENTOR_INJECT_LABEL=$(kubectl get pod test-istio-mentor -n mentor -o jsonpath='{.metadata.labels.sidecar\.istio\.io/inject}' 2>/dev/null || true)
MENTOR_CONTAINERS=$(kubectl get pod test-istio-mentor -n mentor -o jsonpath='{.spec.initContainers[*].name} {.spec.containers[*].name}' 2>/dev/null || true)

if [[ "$MENTOR_INJECT_LABEL" != "true" && ! "$MENTOR_CONTAINERS" =~ "istio-proxy" ]]; then
  log_pass "Non-student pod (mentor) is exempted from automatic sidecar injection (containers: ${MENTOR_CONTAINERS})"
else
  log_fail "Non-student pod received unexpected sidecar injection (inject label: '${MENTOR_INJECT_LABEL}', containers: '${MENTOR_CONTAINERS}')"
fi

MENTOR_PERSON=$(kubectl get pod test-istio-mentor -n mentor -o jsonpath='{.metadata.labels.person}' 2>/dev/null || true)
if [[ "$MENTOR_PERSON" == "mentor" ]]; then
  log_pass "Pod in mentor automatically received label person=mentor"
else
  log_fail "Pod in mentor missing person=mentor label (got: '${MENTOR_PERSON}')"
fi

# ------------------------------------------------------------------------------
# 6. Other Namespaces: no 'person' label at all, even if the pod brings its own
# ------------------------------------------------------------------------------
echo ""
echo "=== Phase 6: Other Namespaces Must Not Carry the 'person' Label ==="

kubectl delete pod test-istio-other -n default --ignore-not-found=true >/dev/null 2>&1 || true

cat <<EOF | kubectl apply -n default -f - >/dev/null 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: test-istio-other
  labels:
    person: student
    keep: me
spec:
  containers:
    - name: test-app
      image: alpine:latest
      command: ["sh", "-c", "sleep 3600"]
      securityContext:
        readOnlyRootFilesystem: true
EOF

OTHER_PERSON=$(kubectl get pod test-istio-other -n default -o jsonpath='{.metadata.labels.person}' 2>/dev/null || true)
OTHER_KEEP=$(kubectl get pod test-istio-other -n default -o jsonpath='{.metadata.labels.keep}' 2>/dev/null || true)
OTHER_INJECT=$(kubectl get pod test-istio-other -n default -o jsonpath='{.metadata.labels.sidecar\.istio\.io/inject}' 2>/dev/null || true)
OTHER_CONTAINERS=$(kubectl get pod test-istio-other -n default -o jsonpath='{.spec.initContainers[*].name} {.spec.containers[*].name}' 2>/dev/null || true)

if [[ -z "$OTHER_PERSON" ]]; then
  log_pass "Pod-supplied person label is removed in a non-tenant namespace (default)"
else
  log_fail "Pod in 'default' still carries person='${OTHER_PERSON}'"
fi

if [[ "$OTHER_KEEP" == "me" ]]; then
  log_pass "Unrelated pod labels are preserved"
else
  log_fail "Unrelated pod label 'keep' was lost (got: '${OTHER_KEEP}')"
fi

if [[ "$OTHER_INJECT" != "true" && ! "$OTHER_CONTAINERS" =~ "istio-proxy" ]]; then
  log_pass "Pod in non-tenant namespace is not injected with a sidecar"
else
  log_fail "Pod in 'default' unexpectedly got a sidecar (inject label: '${OTHER_INJECT}', containers: '${OTHER_CONTAINERS}')"
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo ""
echo "=============================================================================="
echo "Verification Summary: ${PASS} Passed, ${FAIL} Failed"
echo "=============================================================================="

if [[ "$FAIL" -eq 0 ]]; then
  echo -e "\033[0;32mAll Module 04 verification checks passed successfully!\033[0m"
  exit 0
else
  echo -e "\033[0;31mModule 04 verification failed with ${FAIL} error(s).\033[0m"
  exit 1
fi

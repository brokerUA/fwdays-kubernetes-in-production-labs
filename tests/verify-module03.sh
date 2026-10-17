#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Module 03 Platform Engineering Verification Script
# Verifies KinD Cluster, Flux Operator, GitLessOps, Native Admission Policies, and RBAC
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
  kubectl delete pod test-pod-student01 -n student01 --ignore-not-found=true 2>/dev/null || true
  kubectl delete pod test-pod-mentor    -n mentor    --ignore-not-found=true 2>/dev/null || true
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
# 2. Flux Operator & GitLessOps Platform Reconciliation
# ------------------------------------------------------------------------------
echo ""
echo "=== Phase 2: Flux Operator & GitLessOps Checks ==="
FLUX_PODS=$(kubectl get pods -n flux-system --no-headers 2>/dev/null | grep -E 'Running|Completed' | wc -l | tr -d ' ')
if [[ "$FLUX_PODS" -gt 0 ]]; then
  log_pass "Flux Operator and platform controllers are running in flux-system ($FLUX_PODS pods)"
else
  log_fail "Flux controllers not found or not in Running state in flux-system"
fi

# Check OCIRepository
OCI_READY=$(kubectl get ocirepository security-policies -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
if [[ "$OCI_READY" == "True" ]]; then
  log_pass "Flux OCIRepository 'security-policies' is Ready"
else
  log_fail "Flux OCIRepository 'security-policies' is not Ready (status: '${OCI_READY}')"
fi

# Check HelmRelease security-policies
HR_READY=$(kubectl get helmrelease security-policies -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
if [[ "$HR_READY" == "True" ]]; then
  log_pass "Flux HelmRelease 'security-policies' is Ready"
else
  log_fail "Flux HelmRelease 'security-policies' is not Ready (status: '${HR_READY}')"
fi

# ------------------------------------------------------------------------------
# 3. RBAC Persona Isolation
# ------------------------------------------------------------------------------
echo ""
echo "=== Phase 3: RBAC Persona Access Checks ==="

check_can() {
  local desc="$1" verb="$2" resource="$3" ns="$4" sa_ns="$5" sa_name="$6"
  local ns_flags=()
  [[ "$ns" != "cluster-wide" ]] && ns_flags=("-n" "$ns")
  local res
  res=$(kubectl auth can-i "$verb" "$resource" "${ns_flags[@]}" --as="system:serviceaccount:${sa_ns}:${sa_name}" 2>/dev/null || true)
  if [[ "$res" == yes* ]]; then
    log_pass "$desc"
  else
    log_fail "$desc (expected YES, got $res)"
  fi
}

check_cannot() {
  local desc="$1" verb="$2" resource="$3" ns="$4" sa_ns="$5" sa_name="$6"
  local ns_flags=()
  [[ "$ns" != "cluster-wide" ]] && ns_flags=("-n" "$ns")
  local res
  res=$(kubectl auth can-i "$verb" "$resource" "${ns_flags[@]}" --as="system:serviceaccount:${sa_ns}:${sa_name}" 2>/dev/null || true)
  if [[ "$res" == no* ]]; then
    log_pass "$desc"
  else
    log_fail "$desc (expected NO, got $res)"
  fi
}

check_can    "Mentor CAN list pods in student01"           list   pods        student01    mentor    mentor
check_can    "Mentor CAN list pods in student02"           list   pods        student02    mentor    mentor
check_can    "Mentor CAN list pods in student03"           list   pods        student03    mentor    mentor
check_cannot "Mentor CANNOT list nodes cluster-wide"        list   nodes       cluster-wide mentor    mentor

check_can    "Student01 CAN create pods in student01"       create pods        student01    student01 student01
check_cannot "Student01 CANNOT create pods in student02"    create pods        student02    student01 student01

check_can    "Student02 CAN list pods in student01"         list   pods        student01    student02 student02
check_can    "Student02 CAN list pods in default"           list   pods        default      student02 student02
check_cannot "Student02 CANNOT create pods in student01"    create pods        student01    student02 student02
check_cannot "Student02 CANNOT list pods in student02"      list   pods        student02    student02 student02

check_can    "Student03 CAN create pods in student03"       create pods        student03    student03 student03
check_cannot "Student03 CANNOT create pods in student01"    create pods        student01    student03 student03

# ------------------------------------------------------------------------------
# 4. Native Admission Policies Verification (Validating & Mutating Policies)
# ------------------------------------------------------------------------------
echo ""
echo "=== Phase 4: Native Admission Policies Checks ==="

# Readonly rootfs ValidatingAdmissionPolicyBinding check
RO_BINDING=$(kubectl get validatingadmissionpolicybinding require-readonly-rootfs -o name 2>/dev/null || true)
if [[ -n "$RO_BINDING" ]]; then
  log_pass "Native Policy: require-readonly-rootfs ValidatingAdmissionPolicyBinding is active"
else
  log_fail "Native Policy: require-readonly-rootfs ValidatingAdmissionPolicyBinding not found"
fi

# Person label mutation check in student01
echo "Deploying test pod in student01..."
kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-student01
  namespace: student01
spec:
  containers:
  - name: pause
    image: registry.k8s.io/pause:3.9
  restartPolicy: Never
  terminationGracePeriodSeconds: 0
EOF

for _ in $(seq 1 30); do
  phase=$(kubectl get pod test-pod-student01 -n student01 -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [[ -n "$phase" ]] && break
  sleep 1
done

STUDENT_LABEL=$(kubectl get pod test-pod-student01 -n student01 -o jsonpath='{.metadata.labels.person}' 2>/dev/null || true)
if [[ "$STUDENT_LABEL" == "student" ]]; then
  log_pass "Native Policy: pod in student01 automatically mutated with label person=student"
else
  log_fail "Native Policy: pod in student01 expected person=student, got '${STUDENT_LABEL}'"
fi

# Person label mutation check in mentor
echo "Deploying test pod in mentor..."
kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-mentor
  namespace: mentor
spec:
  containers:
  - name: pause
    image: registry.k8s.io/pause:3.9
  restartPolicy: Never
  terminationGracePeriodSeconds: 0
EOF

for _ in $(seq 1 30); do
  phase=$(kubectl get pod test-pod-mentor -n mentor -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [[ -n "$phase" ]] && break
  sleep 1
done

MENTOR_LABEL=$(kubectl get pod test-pod-mentor -n mentor -o jsonpath='{.metadata.labels.person}' 2>/dev/null || true)
if [[ "$MENTOR_LABEL" == "mentor" ]]; then
  log_pass "Native Policy: pod in mentor automatically mutated with label person=mentor"
else
  log_fail "Native Policy: pod in mentor expected person=mentor, got '${MENTOR_LABEL}'"
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo ""
echo "========================================================"
echo " Module 03 Verification Summary"
echo " Passed: $PASS"
echo " Failed: $FAIL"
echo "========================================================"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi

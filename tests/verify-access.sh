#!/usr/bin/env bash
set -euo pipefail

# Prefer admin kubeconfig for verification if available
if [[ -f "infra/terraform/admin.kubeconfig" ]]; then
  export KUBECONFIG="infra/terraform/admin.kubeconfig"
elif [[ -f "../infra/terraform/admin.kubeconfig" ]]; then
  export KUBECONFIG="../infra/terraform/admin.kubeconfig"
fi

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Cleanup trap — removes test pods created during Kyverno label mutation checks
# ---------------------------------------------------------------------------
cleanup() {
  kubectl delete pod test-pod-student01 -n student01 --ignore-not-found=true 2>/dev/null || true
  kubectl delete pod test-pod-mentor    -n mentor    --ignore-not-found=true 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Helper: assert that a ServiceAccount CAN perform an action
#
# Usage: check_can "<description>" <verb> <resource> <namespace|"cluster-wide"> <sa_namespace> <sa_name>
# ---------------------------------------------------------------------------
check_can() {
  local desc="$1"
  local verb="$2"
  local resource="$3"
  local ns="$4"
  local sa_ns="$5"
  local sa_name="$6"

  local ns_flag_arr=()
  if [[ "$ns" != "cluster-wide" ]]; then
    ns_flag_arr=("-n" "$ns")
  fi

  local result
  result=$(kubectl auth can-i "$verb" "$resource" "${ns_flag_arr[@]}" \
             --as="system:serviceaccount:${sa_ns}:${sa_name}" 2>/dev/null || true)

  if [[ "$result" == yes* ]]; then
    echo "[PASS] $desc"
    ((PASS++)) || true
  else
    echo "[FAIL] $desc: expected YES, got NO"
    ((FAIL++)) || true
  fi
}

# ---------------------------------------------------------------------------
# Helper: assert that a ServiceAccount CANNOT perform an action
#
# Usage: check_cannot "<description>" <verb> <resource> <namespace|"cluster-wide"> <sa_namespace> <sa_name>
# ---------------------------------------------------------------------------
check_cannot() {
  local desc="$1"
  local verb="$2"
  local resource="$3"
  local ns="$4"
  local sa_ns="$5"
  local sa_name="$6"

  local ns_flag_arr=()
  if [[ "$ns" != "cluster-wide" ]]; then
    ns_flag_arr=("-n" "$ns")
  fi

  local result
  result=$(kubectl auth can-i "$verb" "$resource" "${ns_flag_arr[@]}" \
             --as="system:serviceaccount:${sa_ns}:${sa_name}" 2>/dev/null || true)

  if [[ "$result" == no* ]]; then
    echo "[PASS] $desc"
    ((PASS++)) || true
  else
    echo "[FAIL] $desc: expected NO, got YES"
    ((FAIL++)) || true
  fi
}

# ---------------------------------------------------------------------------
# RBAC Access Checks  (Requirement 12.2)
# ---------------------------------------------------------------------------
echo "=== RBAC Access Checks ==="

# Mentor — should have read-write access in all three student namespaces
check_can    "Mentor CAN list pods in student01"    list pods student01 mentor mentor
check_can    "Mentor CAN list pods in student02"    list pods student02 mentor mentor
check_can    "Mentor CAN list pods in student03"    list pods student03 mentor mentor

# Mentor — should NOT have cluster-wide node access (no ClusterRoleBinding)
check_cannot "Mentor CANNOT list nodes cluster-wide" list nodes cluster-wide mentor mentor

# Student01 — read-write in own namespace only
check_can    "Student01 CAN create pods in student01"     create pods student01 student01 student01
check_cannot "Student01 CANNOT create pods in student02"  create pods student02 student01 student01

# Student02 — read-only in student01 and default; no access in student02
check_can    "Student02 CAN list pods in student01"       list pods student01 student02 student02
check_can    "Student02 CAN list pods in default"         list pods default    student02 student02
check_cannot "Student02 CANNOT create pods in student01"  create pods student01 student02 student02
check_cannot "Student02 CANNOT list pods in student02"    list pods student02  student02 student02

# Student03 — read-write in own namespace only
check_can    "Student03 CAN create pods in student03"     create pods student03 student03 student03
check_cannot "Student03 CANNOT create pods in student01"  create pods student01 student03 student03

# ---------------------------------------------------------------------------
# Kyverno Policy Checks  (Requirements 12.3, 12.4, 12.5)
# ---------------------------------------------------------------------------
echo ""
echo "=== Kyverno Policy Checks ==="

# --- Label mutation: student namespace → person=student  (Requirement 12.3) ---
echo "Creating test pod in student01 to verify PersonLabel mutation..."
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

# Wait for the pod to be admitted (up to 30 s)
for i in $(seq 1 30); do
  phase=$(kubectl get pod test-pod-student01 -n student01 \
            -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [[ -n "$phase" ]] && break
  sleep 1
done

person_label=$(kubectl get pod test-pod-student01 -n student01 \
                 -o jsonpath='{.metadata.labels.person}' 2>/dev/null || true)

if [[ "$person_label" == "student" ]]; then
  echo "[PASS] Kyverno: pod in student01 has label person=student"
  ((PASS++)) || true
else
  echo "[FAIL] Kyverno: pod in student01 expected label person=student, got '${person_label}'"
  ((FAIL++)) || true
fi

# --- Label mutation: mentor namespace → person=mentor  (Requirement 12.4) ---
echo "Creating test pod in mentor to verify PersonLabel mutation..."
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

for i in $(seq 1 30); do
  phase=$(kubectl get pod test-pod-mentor -n mentor \
            -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [[ -n "$phase" ]] && break
  sleep 1
done

person_label=$(kubectl get pod test-pod-mentor -n mentor \
                 -o jsonpath='{.metadata.labels.person}' 2>/dev/null || true)

if [[ "$person_label" == "mentor" ]]; then
  echo "[PASS] Kyverno: pod in mentor has label person=mentor"
  ((PASS++)) || true
else
  echo "[FAIL] Kyverno: pod in mentor expected label person=mentor, got '${person_label}'"
  ((FAIL++)) || true
fi

# --- Policy existence and mode check  (Requirement 12.5) ---
echo "Checking require-readonly-rootfs ClusterPolicy..."
action=$(kubectl get clusterpolicy require-readonly-rootfs \
           -o jsonpath='{.spec.validationFailureAction}' 2>/dev/null || true)

if [[ "$action" == "Audit" ]]; then
  echo "[PASS] Kyverno: require-readonly-rootfs ClusterPolicy has validationFailureAction=Audit"
  ((PASS++)) || true
else
  echo "[FAIL] Kyverno: require-readonly-rootfs ClusterPolicy expected validationFailureAction=Audit, got '${action}'"
  ((FAIL++)) || true
fi

# ---------------------------------------------------------------------------
# Summary  (Requirements 12.6, 12.7)
# ---------------------------------------------------------------------------
echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi

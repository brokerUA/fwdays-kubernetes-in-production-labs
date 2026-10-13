# Module 02 – Security & Policy as Code

This guide walks you through setting up the complete Module 02 lab environment: a local Kubernetes cluster with scoped RBAC users, Kyverno admission policies, and two demo microservices — all provisioned in a single `terraform apply`.

---

## Prerequisites

Make sure the following tools are installed on your machine before you begin.

| Tool | Purpose |
|---|---|
| **Docker Desktop** (or equivalent Docker daemon) | Required by `kind` to run cluster nodes as containers |
| **mise** | Manages all pinned tool versions and environment variables |
| **Git** | Required to clone the repository |

> **Note:** The exact versions of `terraform`, `kubectl`, `helm`, and `kind` are managed by `mise` — you do not need to install them manually.

---

## Repository Setup

Clone the repository and switch to the working branch:

```bash
git clone https://github.com/brokerUA/fwdays-kubernetes-in-production-labs.git
cd fwdays-kubernetes-in-production-labs
git checkout feature/init
```

Verify you are on the correct branch:

```bash
git branch --show-current
# expected output: feature/init
```

---

## Running `mise install`

Install all pinned tool versions declared in `mise.toml`:

```bash
mise install
```

This installs the following tools at exact versions:

| Tool | Version  |
|---|----------|
| `terraform` | `1.16.5` |
| `kubectl` | `1.37.1` |
| `helm` | `4.3.0`  |
| `kind` | `0.33.0` |
| `k9s` | `0.51.0` |

Verify the installations:

```bash
mise exec -- terraform version
mise exec -- kubectl version --client
mise exec -- helm version
mise exec -- kind version
mise exec -- k9s version
```

---

## Provisioning the Cluster

All infrastructure is managed by a single Terraform workspace located in `infra/terraform/`.

```bash
cd infra/terraform
terraform init
terraform apply
```

When prompted, type `yes` to confirm. The apply will:

1. Create a local `kind` cluster named `k8s-in-production` with 1 control-plane and 3 worker nodes
2. Create four namespaces: `mentor`, `student01`, `student02`, `student03`
3. Create four ServiceAccounts and generate kubeconfig files at the repo root
4. Apply RBAC Roles and RoleBindings for all users
5. Install Kyverno via Helm
6. Deploy the `require-readonly-rootfs` and `add-person-label` ClusterPolicies

After the apply completes, four kubeconfig files will be written to the repo root:

```
kubeconfig-mentor.yaml
kubeconfig-student01.yaml
kubeconfig-student02.yaml
kubeconfig-student03.yaml
```

Verify the cluster is reachable (expect 4 nodes Ready: 1 control-plane and 3 workers):

```bash
kubectl get nodes
```

You can test user access using the generated user-scoped kubeconfigs directly:

```bash
export KUBECONFIG=kubeconfig-student01.yaml
kubectl get pods --namespace=student01
```

---

## Verifying RBAC Permissions

Use `kubectl auth can-i` with `--as` impersonation against the admin kubeconfig to verify each user's permissions without switching kubeconfigs.

### Mentor

The mentor has read-write access to all three student namespaces, but no cluster-wide access.

```bash
# Mentor CAN list pods in student01 (expect: yes)
kubectl auth can-i list pods -n student01 \
  --as=system:serviceaccount:mentor:mentor

# Mentor CAN list pods in student02 (expect: yes)
kubectl auth can-i list pods -n student02 \
  --as=system:serviceaccount:mentor:mentor

# Mentor CAN list pods in student03 (expect: yes)
kubectl auth can-i list pods -n student03 \
  --as=system:serviceaccount:mentor:mentor

# Mentor CANNOT list nodes cluster-wide (expect: no)
kubectl auth can-i list nodes \
  --as=system:serviceaccount:mentor:mentor
```

### Student01

Student01 has read-write access only in the `student01` namespace.

```bash
# Student01 CAN create pods in student01 (expect: yes)
kubectl auth can-i create pods -n student01 \
  --as=system:serviceaccount:student01:student01

# Student01 CANNOT create pods in student02 (expect: no)
kubectl auth can-i create pods -n student02 \
  --as=system:serviceaccount:student01:student01
```

### Student02

Student02 has read-only access to `student01` and `default`, and no access to `student02`.

```bash
# Student02 CAN list pods in student01 (expect: yes)
kubectl auth can-i list pods -n student01 \
  --as=system:serviceaccount:student02:student02

# Student02 CAN list pods in default (expect: yes)
kubectl auth can-i list pods -n default \
  --as=system:serviceaccount:student02:student02

# Student02 CANNOT create pods in student01 (expect: no)
kubectl auth can-i create pods -n student01 \
  --as=system:serviceaccount:student02:student02

# Student02 CANNOT list pods in student02 (expect: no)
kubectl auth can-i list pods -n student02 \
  --as=system:serviceaccount:student02:student02
```

### Student03

Student03 has read-write access only in the `student03` namespace.

```bash
# Student03 CAN create pods in student03 (expect: yes)
kubectl auth can-i create pods -n student03 \
  --as=system:serviceaccount:student03:student03

# Student03 CANNOT create pods in student01 (expect: no)
kubectl auth can-i create pods -n student01 \
  --as=system:serviceaccount:student03:student03
```

---

## Verifying Kyverno Policies

### Check ClusterPolicy Existence

Verify both ClusterPolicies are installed and their status:

```bash
kubectl get clusterpolicy
```

Expected output shows two policies:

```
NAME                     ADMISSION   BACKGROUND   VALIDATE ACTION   READY   AGE
add-person-label         true        true         Enforce           True    ...
require-readonly-rootfs  true        true         Audit             True    ...
```

Inspect a policy in detail:

```bash
kubectl get clusterpolicy require-readonly-rootfs -o yaml
kubectl get clusterpolicy add-person-label -o yaml
```

### Check PolicyReports

After pods are created in the cluster, Kyverno generates `PolicyReport` resources recording compliance results:

```bash
# List all PolicyReports across all namespaces
kubectl get policyreport -A

# Inspect a specific report in student01
kubectl get policyreport -n student01 -o yaml

# Check the ClusterPolicyReport for cluster-scoped resources
kubectl get clusterpolicyreport -o yaml
```

### Test Label Mutation

Create a test pod in `student01` and verify the `person: student` label is added automatically:

```bash
kubectl run test-pod \
  --image=nginx:alpine \
  --restart=Never \
  -n student01 \
  --overrides='{"spec":{"containers":[{"name":"test-pod","image":"nginx:alpine","securityContext":{"readOnlyRootFilesystem":true}}]}}'

kubectl get pod test-pod -n student01 --show-labels

# Clean up
kubectl delete pod test-pod -n student01
```

The output should show `person=student` in the labels column.

Create a test pod in `mentor` and verify the `person: mentor` label:

```bash
kubectl run test-pod \
  --image=nginx:alpine \
  --restart=Never \
  -n mentor \
  --overrides='{"spec":{"containers":[{"name":"test-pod","image":"nginx:alpine","securityContext":{"readOnlyRootFilesystem":true}}]}}'

kubectl get pod test-pod -n mentor --show-labels

# Clean up
kubectl delete pod test-pod -n mentor
```

---

## Running Automated Tests

The test suite verifies all RBAC rules and Kyverno policy behaviors in one command:

```bash
mise run test:access
```

This executes `tests/verify-access.sh`, which runs:

- 10 RBAC assertions using `kubectl auth can-i` with `--as` impersonation
- Kyverno label mutation checks by creating pods in `student01` and `mentor`
- A ClusterPolicy existence and mode check for `require-readonly-rootfs`

Each check prints `[PASS]` or `[FAIL] <description>: expected <X>, got <Y>`. The script exits with code `0` only if every check passes.

Example successful output:

```
[PASS] mentor can list pods in student01
[PASS] mentor can list pods in student02
[PASS] mentor can list pods in student03
[PASS] mentor cannot list nodes
[PASS] student01 can create pods in student01
[PASS] student01 cannot create pods in student02
[PASS] student02 can list pods in student01
[PASS] student02 can list pods in default
[PASS] student02 cannot create pods in student01
[PASS] student02 cannot list pods in student02
[PASS] student03 can create pods in student03
[PASS] student03 cannot create pods in student01
[PASS] person label is 'student' in student01
[PASS] person label is 'mentor' in mentor namespace
[PASS] require-readonly-rootfs ClusterPolicy is in Audit mode
All checks passed.
```

---

## Deploying Demo Applications

### Build images and load them into kind

This repo uses `kind load docker-image` (no local registry). Build the images locally and load them into the cluster:

```bash
# Go service
docker build -t go-service:latest apps/go-service/
kind load docker-image go-service:latest --name k8s-in-production

# Flask service
docker build -t flask-service:latest apps/flask-service/
kind load docker-image flask-service:latest --name k8s-in-production
```

### Apply Manifests

```bash
kubectl apply -f infra/terraform/manifests/
```

Verify the deployments are running:

```bash
kubectl get deployments -n student01
kubectl get pods -n student01
kubectl get services -n student01
```

### Access the Services

Forward a local port to each service to test them:

```bash
# Go service (port 8080)
kubectl port-forward service/go-service 8080:8080 -n student01
curl http://localhost:8080
# expected: Hello from Go service

# Flask service (port 5000)
kubectl port-forward service/flask-service 5000:5000 -n student01
curl http://localhost:5000
# expected: Hello from Flask service
```

---

## Teardown

To remove all provisioned resources including the kind cluster:

```bash
cd infra/terraform
terraform destroy
```

When prompted, type `yes` to confirm. This removes:

- The kind cluster and all nodes
- All Kubernetes resources created by Terraform
- The Kyverno installation

The generated kubeconfig files at the repo root are not deleted by Terraform but become invalid after the cluster is destroyed. You can remove them manually:

```bash
rm -f kubeconfig-mentor.yaml kubeconfig-student01.yaml \
      kubeconfig-student02.yaml kubeconfig-student03.yaml
```

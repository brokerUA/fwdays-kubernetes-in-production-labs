# Module 03 – Platform Engineering (KinD, Flux Operator, GitLessOps, and OCI)

This guide walks you through setting up the complete Module 03 platform engineering environment: a local multi-node **KinD (Kubernetes in Docker)** cluster provisioned via **Bootstrap Terraform**, automated cluster reconciliation via **Flux Operator** pulling Helm charts and platform manifests as immutable **OCI artifacts** from **GitHub Container Registry (GHCR)** (Pure GitLessOps), and native Kubernetes admission policy enforcement (ValidatingAdmissionPolicy and MutatingAdmissionPolicy).

---

## Architecture Overview

Module 03 implements a clean three-layer operator-driven architecture:
1. **Cluster Infrastructure Layer (Bootstrap Terraform)**: Provisions a local multi-node KinD cluster (1 control-plane and 3 worker nodes) with IPVS proxy mode and enabled native admission policy feature gates using `tehcyx/kind` provider in `infra/`. Creates the baseline `cluster-config` ConfigMap (defining `OCI_REGISTRY_OWNER`).
2. **Platform Operator Layer (Flux Operator & OCI Root Reconciliation)**: Deploys `flux-operator` and `flux-instance` controllers directly into Kubernetes using official OCI Helm charts, configuring Flux GitOps Root Reconciliation against the OCI platform artifact (`oci://ghcr.io/<owner>/platform-flux:latest`).
3. **Cluster Default Resources & GitLessOps Layer**: Reconciled automatically by Flux via `postBuild.substituteFrom` (pulling variables from `cluster-config` ConfigMap):
   - **Security Policies & Personas**: Packaged as an OCI Helm artifact (`oci://ghcr.io/<owner>/charts/security-policies`), deploying namespaces (`mentor`, `student01-03`), ServiceAccounts, RBAC roles/bindings, and native admission/mutation policies (`ValidatingAdmissionPolicy` and `MutatingAdmissionPolicy`).
   - **Application Workloads**: Microservices (`flask-service` and `go-service`) using the generic `charts/app-service` DRY chart packaged as an OCI Helm artifact (`oci://ghcr.io/<owner>/charts/app-service`) and continuously reconciled into tenant namespaces via Flux `HelmRelease`.

```mermaid
graph TD
  subgraph Local & CI Environment
    Dev[Developer Workstation]
    GHA_Charts[GitHub Actions: publish-charts-oci]
    GHA_Platform[GitHub Actions: publish-platform-oci]
  end

  subgraph OCI Registry GHCR
    GHCR_Charts[Charts: security-policies, app-service]
    GHCR_Platform[Platform: platform-flux:latest]
    FluxGHCR[ControlPlane Charts: flux-operator, flux-instance]
  end

  subgraph Local KinD Kubernetes Cluster
    subgraph flux-system Namespace
      FluxOp[Flux Operator]
      FluxInst[Flux Instance Controllers]
      ConfigMap[ConfigMap: cluster-config<br/>OCI_REGISTRY_OWNER]
    end
    
    subgraph Platform Operators & Workloads
      APIServer[kube-apiserver CEL Engine<br/>Validating & Mutating Admission Policies]
      Workloads[Namespaces: mentor, student01-03]
    end
  end

  Dev -->|1. terraform apply| Local KinD Kubernetes Cluster
  Terraform -->|2. helm install flux-operator| FluxOp
  FluxOp -->|3. manage controllers & sync| FluxInst
  FluxInst -->|4. Root Sync from OCI| GHCR_Platform
  FluxInst -->|5. Substitute OCI URL via| ConfigMap
  Dev -->|git push charts/| GHA_Charts
  Dev -->|git push gitlessops/| GHA_Platform
  GHA_Charts -->|6. helm push OCI| GHCR_Charts
  GHA_Platform -->|7. flux push artifact OCI| GHCR_Platform
  FluxInst -->|8. Pull OCI Charts| GHCR_Charts
  FluxInst -->|9. HelmRelease Reconcile| Workloads
  APIServer -->|10. Enforce CEL Policies & Mutate| Workloads
```

---

## Prerequisites

Make sure the following tools and credentials are ready before you begin:

| Tool / Requirement | Purpose |
|---|---|
| **Docker Engine / Desktop** | Required for running KinD cluster nodes as local containers |
| **GitHub Account & PAT** | Personal Access Token with `read:packages` / `write:packages` scope for GHCR |
| **mise** | Manages pinned CLI tool versions (`terraform`, `kubectl`, `helm`, `flux2`, `kind`, `k9s`) |
| **Git** | Repository version control |

---

## Pinned Tooling Installation

Install all pinned tools declared in `mise.toml`:

```bash
mise install
```

Verify your tool versions:

```bash
mise exec -- terraform version
mise exec -- kubectl version --client
mise exec -- helm version
mise exec -- kind version
mise exec -- flux --version
```

---

## Step 1: Publish OCI Artifacts via CI/CD

OCI Helm charts and platform manifests are published to GHCR automatically via GitHub Actions:

1. **Publish Charts** (`.github/workflows/publish-charts-oci.yaml`):
   - Triggered on changes to `charts/**`.
   - Lints, packages, and pushes `charts/security-policies` and `charts/app-service` to `oci://ghcr.io/<owner>/charts/<chart-name>`.

2. **Publish Platform Manifests** (`.github/workflows/publish-platform-oci.yaml`):
   - Triggered on changes to `gitlessops/**`.
   - Packages and pushes `./gitlessops` manifests as an OCI artifact to `oci://ghcr.io/<owner>/platform-flux:latest`.

---

## Step 2: Bootstrap KinD Cluster & Operators via Terraform

The bootstrap Terraform workspace is located directly in `infra/`. It provisions the KinD cluster, installs the Flux Operator and Flux Instance with OCI root reconciliation, and creates baseline cluster configurations.

1. Navigate to the Terraform bootstrap directory:
   ```bash
   cd infra
   ```

2. Initialize Terraform providers:
   ```bash
   terraform init
   ```

3. Export your GitHub account name for GHCR:
   ```bash
   export TF_VAR_ghcr_owner="<your-github-username>"
   ```

4. Apply the infrastructure:
   ```bash
   terraform apply
   ```
   *When prompted, enter `yes` to confirm.*

5. Verify that the KinD nodes and Flux Operator controllers are running:
   ```bash
   export KUBECONFIG="$(pwd)/k8s-in-production-config"
   kubectl get nodes
   kubectl get pods -n flux-system
   ```

---

## Step 3: Trigger & Monitor GitLessOps Reconciliation

Flux Operator automatically monitors the OCI repository and reconciles the cluster resources:

1. Check OCI repository status:
   ```bash
   flux get sources oci -n flux-system
   ```

2. Check HelmRelease status:
   ```bash
   flux get helmreleases -A
   ```

3. Force an immediate reconciliation if needed:
   ```bash
   flux reconcile source oci flux-system -n flux-system
   flux reconcile kustomization flux-system -n flux-system
   flux reconcile kustomization apps -n flux-system
   ```

---

## Step 4: Generate Persona Kubeconfigs

Generate scoped kubeconfigs for `mentor`, `student01`, `student02`, and `student03`:

```bash
bash scripts/generate-user-kubeconfigs.sh
```

---

## Step 5: Verification & Automated Testing

Execute the comprehensive test suite to validate the KinD cluster, Flux Operator, GitLessOps reconciliation, RBAC isolation, and native admission policy enforcement:

```bash
mise run test:module03
```

Or run the test script directly:

```bash
bash tests/verify-module03.sh
```

---

## Teardown & Cleanup

To destroy the KinD cluster and all resources:

```bash
cd infra
terraform destroy -auto-approve
```

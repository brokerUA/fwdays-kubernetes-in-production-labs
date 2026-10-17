# Kubernetes in Production Labs

Hands-on platform engineering lab implementing **GitLessOps**, Kubernetes CEL admission policies, and multi-tenant workload management.

---

### Architecture & How It Works

```text
[ CI / GitHub Actions ]
       │
       ├─► Build & Push Apps        ──► ghcr.io/<owner>/<app>:<tag>
       ├─► Package & Push Charts    ──► oci://ghcr.io/<owner>/charts/<chart>
       └─► Package & Push Manifests ──► oci://ghcr.io/<owner>/platform-flux:<tag>
                                                   │
                                                   ▼
                                         [ KinD Cluster ]
                                         Flux Operator (OCI)
                                                   │
                         ┌─────────────────────────┴─────────────────────────┐
                         ▼                                                   ▼
               [ Platform Layer ]                                   [ Tenant Workloads ]
           - Namespaces & RBAC                                  - student01-flask-service
           - CEL Admission Policies                             - student01-go-service
```

---

### Key Components

#### 1. GitLessOps via OCI Artifacts
- **Zero Git Credentials:** Cluster pulls declarative state exclusively from GitHub Container Registry (GHCR) as immutable OCI artifacts.
- **Flux Operator:** Reconciles root platform manifests (`platform-flux`) and Helm charts directly from OCI registries.
- **Dynamic Scoping:** `${OCI_REGISTRY_OWNER}` is injected at runtime via cluster `ConfigMap/cluster-config`.

#### 2. CI/CD Pipelines (`.github/workflows/`)
- **`publish-apps-oci.yaml`:** Builds multi-arch (`amd64`/`arm64`) Docker images for `flask-service` and `go-service`, pushes to GHCR.
- **`publish-charts-oci.yaml`:** Lints, packages, and pushes Helm charts (`security-policies`, `app-service`) to GHCR as OCI artifacts.
- **`publish-platform-oci.yaml`:** Packages the `./gitlessops` manifest tree into the `platform-flux` OCI artifact.
- *All workflows support manual execution (`workflow_dispatch`) with custom version tagging.*

#### 3. Application Deployment & Releases
- **Decoupled Architecture:** Infrastructure code (`infra/`) contains no app-specific logic.
- **Manifest-Driven Versions:** Workload versions and image tags are managed purely inside `gitlessops/apps/releases/<service>.yaml`.
- **Release Workflow:**
  1. Push new container image via CI.
  2. Update `spec.values.image.tag` in `gitlessops/apps/releases/<service>.yaml`.
  3. Push to Git -> CI publishes new `platform-flux` OCI artifact -> Flux synchronizes changes to cluster.

---

### Quick Start

```bash
# 1. Install CLI tools
mise install

# 2. Provision KinD cluster and Flux Operator
cd infra
export TF_VAR_ghcr_owner="<your-github-username-in-lowercase>"
terraform init && terraform apply

# 3. Configure local access
cd ..
export KUBECONFIG="$(pwd)/infra/k8s-in-production-config"

# 4. Verify deployment
flux get sources oci -n flux-system
flux get helmreleases -A
kubectl get pods -n student01

# 5. Run automated validation test suite
bash tests/verify-module03.sh
bash tests/verify-access.sh
```

---

### Documentation

- [Module 02 – Security & Policy as Code](docs/module-02-security-policy.md)
- [Module 03 – Platform Engineering (KinD, Flux Operator, & GitLessOps)](docs/module-03-platform-engineering.md)
- [Module 04 – Service Mesh (Istio Sidecar & Native CEL Policies)](docs/module-04-service-mesh.md)

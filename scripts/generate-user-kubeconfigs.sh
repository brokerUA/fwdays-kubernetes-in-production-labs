#!/usr/bin/env bash
set -euo pipefail

# Generates persona-specific kubeconfigs using ServiceAccount tokens on KinD or Kubernetes clusters.

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

OUTPUT_DIR="${1:-.}"
mkdir -p "$OUTPUT_DIR"

CURRENT_CONTEXT=$(kubectl config current-context)
CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}')
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[?(@.name=="'$CLUSTER_NAME'")].cluster.server}')
CA_DATA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[?(@.name=="'$CLUSTER_NAME'")].cluster.certificate-authority-data}')

declare -A USERS=(
  ["mentor"]="mentor"
  ["student01"]="student01"
  ["student02"]="student02"
  ["student03"]="student03"
)

echo "========================================================"
echo " Generating Persona Kubeconfigs"
echo " Cluster: $CLUSTER_NAME ($SERVER)"
echo " Output:  $OUTPUT_DIR"
echo "========================================================"

for USER in "${!USERS[@]}"; do
  NS="${USERS[$USER]}"
  echo "==> Generating kubeconfig for $USER (namespace: $NS)..."

  # Attempt to retrieve token from Secret first, fallback to token request
  TOKEN=$(kubectl get secret "${USER}-token" -n "$NS" -o jsonpath='{.data.token}' 2>/dev/null | (base64 -d 2>/dev/null || base64 -D 2>/dev/null) || true)
  
  if [ -z "$TOKEN" ]; then
    echo "    Token secret not found, requesting token via ServiceAccount API..."
    TOKEN=$(kubectl create token "$USER" -n "$NS" --duration=24h)
  fi

  OUT_FILE="$OUTPUT_DIR/kubeconfig-${USER}.yaml"
  cat <<EOF > "$OUT_FILE"
apiVersion: v1
kind: Config
preferences: {}
current-context: ${USER}-context

clusters:
  - name: ${CLUSTER_NAME}
    cluster:
      server: ${SERVER}
      certificate-authority-data: ${CA_DATA}

contexts:
  - name: ${USER}-context
    context:
      cluster: ${CLUSTER_NAME}
      namespace: ${NS}
      user: ${USER}

users:
  - name: ${USER}
    user:
      token: ${TOKEN}
EOF

  chmod 600 "$OUT_FILE"
  echo "    Wrote $OUT_FILE"
done

echo "========================================================"
echo " All kubeconfig files generated successfully!"
echo "========================================================"

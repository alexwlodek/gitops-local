#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-dev-cluster}"
KIND_CONFIG="${KIND_CONFIG:-infra/kind/kind-cluster.yaml}"

ARGOCD_NS="${ARGOCD_NS:-argocd}"
ROOT_APP_PATH="${ROOT_APP_PATH:-gitops/clusters/dev/root-app.yaml}"

# port-forward dla ArgoCD UI (żeby nie kolidowało z echo na 8080)
ARGOCD_LOCAL_PORT="${ARGOCD_LOCAL_PORT:-8090}"

log() { echo "[+] $*"; }
warn() { echo "[!] $*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "[x] Missing dependency: $1" >&2; exit 1; }
}

need_cmd kind
need_cmd kubectl
need_cmd base64

log "Using cluster name: ${CLUSTER_NAME}"
log "Using kind config: ${KIND_CONFIG}"
log "Using Argo CD namespace: ${ARGOCD_NS}"
log "Using root app: ${ROOT_APP_PATH}"

# 1) Create/ensure KIND cluster
if kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  log "KIND cluster '${CLUSTER_NAME}' already exists. Skipping create."
else
  log "Creating KIND cluster '${CLUSTER_NAME}'..."
  kind create cluster --name "${CLUSTER_NAME}" --config "${KIND_CONFIG}"
fi

# Ensure kubectl context points to this cluster
KUBE_CONTEXT="kind-${CLUSTER_NAME}"
if kubectl config get-contexts -o name | grep -qx "${KUBE_CONTEXT}"; then
  kubectl config use-context "${KUBE_CONTEXT}" >/dev/null
  log "Switched kubectl context to '${KUBE_CONTEXT}'."
else
  warn "Expected kubectl context '${KUBE_CONTEXT}' not found. Continuing with current context:"
  kubectl config current-context
fi

log "Labeling nodes for ingress scheduling..."
kubectl get nodes -o name | xargs -I{} kubectl label {} ingress-ready=true --overwrite >/dev/null 2>&1 || true


# 2) Install Argo CD
if kubectl get ns "${ARGOCD_NS}" >/dev/null 2>&1; then
  log "Namespace '${ARGOCD_NS}' already exists. Skipping namespace create."
else
  log "Creating namespace '${ARGOCD_NS}'..."
  kubectl create namespace "${ARGOCD_NS}"
fi

log "Installing/Upgrading Argo CD..."
kubectl apply -n "${ARGOCD_NS}" \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3) Wait until Argo CD core components are ready
log "Waiting for Argo CD deployments to be available..."
kubectl -n "${ARGOCD_NS}" wait --for=condition=Available deployment/argocd-server --timeout=300s
kubectl -n "${ARGOCD_NS}" wait --for=condition=Available deployment/argocd-repo-server --timeout=300s
kubectl -n "${ARGOCD_NS}" wait --for=condition=Available deployment/argocd-applicationset-controller --timeout=300s || true
kubectl -n "${ARGOCD_NS}" wait --for=condition=Available deployment/argocd-redis --timeout=300s || true
kubectl -n "${ARGOCD_NS}" wait --for=condition=Available deployment/argocd-notifications-controller --timeout=300s || true
kubectl -n "${ARGOCD_NS}" rollout status statefulset/argocd-application-controller --timeout=300s

# Optional: argocd-dex-server may be disabled depending on config; wait only if exists
if kubectl -n "${ARGOCD_NS}" get deployment argocd-dex-server >/dev/null 2>&1; then
  kubectl -n "${ARGOCD_NS}" wait --for=condition=Available deployment/argocd-dex-server --timeout=300s
fi

# 4) Print initial admin password (if secret exists; it disappears after password change in some setups)
log "Obtaining Argo CD initial admin password..."
if kubectl -n "${ARGOCD_NS}" get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  kubectl -n "${ARGOCD_NS}" get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d; echo
else
  warn "Secret argocd-initial-admin-secret not found. Password may have been rotated/disabled."
fi

# 5) Apply root app (App-of-Apps)
log "Applying root app: ${ROOT_APP_PATH}"
kubectl apply -f "${ROOT_APP_PATH}"


log "Done."

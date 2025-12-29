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
kubectl -n "${ARGOCD_NS}" wait --for=condition=Available deployment/argocd-application-controller --timeout=300s

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

# 6) (Optional) Start port-forward in background
log "Starting Argo CD UI port-forward in background on https://localhost:${ARGOCD_LOCAL_PORT}"
PF_PID_FILE=".argocd-portforward.pid"

# Kill old PF if exists
if [[ -f "${PF_PID_FILE}" ]]; then
  oldpid="$(cat "${PF_PID_FILE}" || true)"
  if [[ -n "${oldpid}" ]] && ps -p "${oldpid}" >/dev/null 2>&1; then
    warn "Existing Argo CD port-forward PID ${oldpid} found. Stopping it."
    kill "${oldpid}" || true
  fi
  rm -f "${PF_PID_FILE}"
fi

# Run in background
nohup kubectl -n "${ARGOCD_NS}" port-forward svc/argocd-server "${ARGOCD_LOCAL_PORT}:443" \
  >/tmp/argocd-portforward.log 2>&1 &

echo $! > "${PF_PID_FILE}"
log "Port-forward PID: $(cat "${PF_PID_FILE}")"
log "Log file: /tmp/argocd-portforward.log"
log "Done."

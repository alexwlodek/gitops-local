#!/bin/bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-dev-cluster}"
INGRESS_NS="ingress-nginx"
DEMO_NS="demo"
VALUES_FILE="helm/ingress-nginx-values.yaml"

echo "[+] Labeling node for ingress scheduling"
kubectl label node "${CLUSTER_NAME}-control-plane" ingress-ready=true --overwrite

echo "[+] Installing/Upgrading ingress-nginx via Helm"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx  >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n "${INGRESS_NS}" --create-namespace \
  -f "${VALUES_FILE}"

echo "[+] Waiting for ingress controller"
kubectl -n "${INGRESS_NS}" wait \
  --for=condition=Ready pod \
  -l app.kubernetes.io/component=controller \
  --timeout=300s

echo "[+] Creating demo namespace"
kubectl get ns "${DEMO_NS}" >/dev/null 2>&1 || kubectl create ns "${DEMO_NS}"

echo "[+] Deploying demo app via Helm"
helm upgrade --install echo ./charts/echo -n "${DEMO_NS}" --create-namespace

echo "[+] Waiting for demo app to be Ready"
kubectl -n "${DEMO_NS}" rollout status deployment/echo --timeout=180s

echo "[+] Waiting for service endpoints"
# czekamy aż Service ma co najmniej 1 endpoint
for i in {1..60}; do
  EP="$(kubectl -n demo get endpoints echo -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)"
  if [ -n "${EP}" ]; then
    echo "[=] Endpoints ready: ${EP}"
    break
  fi
  sleep 1
done

if [ -z "${EP:-}" ]; then
  echo "[!] No endpoints for service echo"
  kubectl -n demo get pods,svc,endpoints,ingress -o wide || true
  exit 1
fi

echo "[+] Starting port-forward to ingress-nginx (dev mode)"
LOCAL_PORT="${LOCAL_PORT:-8080}"
./scripts/port-forward-ingress.sh

echo "[+] Smoke test (via port-forward on localhost:${LOCAL_PORT})"
for i in {1..30}; do
  if curl -fsS -H "Host: echo.local" "http://127.0.0.1:${LOCAL_PORT}/" >/dev/null; then
    echo "[=] Smoke test OK"
    break
  fi
  echo "[=] Smoke test not ready yet (attempt ${i}/30), retrying..."
  sleep 1
done

curl -fsS -H "Host: echo.local" "http://127.0.0.1:${LOCAL_PORT}/" | head -c 200 && echo

#!/bin/bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-dev-cluster}"
CONFIG="${CONFIG:-infra/kind/kind-cluster.yaml}"

if kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  echo "[=] Cluster ${CLUSTER_NAME} already exists"
else
  echo "[+] Creating cluster ${CLUSTER_NAME}"
  kind create cluster --name "${CLUSTER_NAME}" --config "${CONFIG}"
fi

kubectl cluster-info

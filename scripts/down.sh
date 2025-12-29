#!/bin/bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-dev-cluster}"
kind delete cluster --name "${CLUSTER_NAME}"

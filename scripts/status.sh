#!/bin/bash
set -euo pipefail

kubectl get nodes -o wide
echo
kubectl -n ingress-nginx get pods,svc -o wide
echo
kubectl -n demo get deploy,svc,pods,ingress,endpoints -o wide
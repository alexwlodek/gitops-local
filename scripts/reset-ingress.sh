#!/bin/bash
set -euo pipefail

kubectl delete ns ingress-nginx --ignore-not-found --wait=true

kubectl delete clusterrole ingress-nginx ingress-nginx-admission --ignore-not-found
kubectl delete clusterrolebinding ingress-nginx ingress-nginx-admission --ignore-not-found
kubectl delete validatingwebhookconfiguration ingress-nginx-admission --ignore-not-found
kubectl delete ingressclass nginx --ignore-not-found

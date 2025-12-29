# Local Kubernetes GitOps Playground (KIND + Argo CD)

This repository provides a **local Kubernetes GitOps playground** built using **KIND** and **Argo CD**.
It serves as a clean, reusable foundation for experimenting with Kubernetes, GitOps workflows, and platform-level components before moving to cloud-managed clusters.

The setup is intentionally minimal, stable, and production-oriented in its structure.

---

## What this repository provides

- Local Kubernetes cluster based on KIND
- Argo CD installed as the GitOps controller
- App-of-Apps pattern for cluster state management
- ingress-nginx as a single entry point to the cluster
- Example application (`echo`) managed fully via GitOps
- No manual Helm installs or kubectl apply for applications
- No port-forwarding required for accessing services

All workloads are deployed and reconciled directly from Git.

---

## Architecture overview

A single ingress entry point is exposed to the host machine:

- HTTP: localhost:8080
- HTTPS: localhost:8443

Ingress routes traffic based on Host headers:

- echo.local    → example application
- argocd.local  → Argo CD UI

High-level flow:

Host (Browser / curl)
→ KIND extraPortMappings (8080 / 8443)
→ ingress-nginx (NodePort)
→ Ingress (host-based routing)
→ Services (ClusterIP)
→ Pods

---

## Prerequisites

The following tools must be installed locally:

- Docker
- kind
- kubectl
- git

Tested with:
- Windows + WSL2
- Docker Desktop

---

## Starting the cluster

Create the cluster and bootstrap Argo CD:

./scripts/up.sh

This script performs the following actions:

1. Creates a KIND cluster (if it does not exist)
2. Installs Argo CD
3. Waits until Argo CD is ready
4. Applies the root GitOps application

From this point forward, Argo CD manages all applications.

---

## Accessing the applications

### Update hosts file

Add the following entries on the host machine:

127.0.0.1 argocd.local
127.0.0.1 echo.local

### Argo CD UI

https://argocd.local:8443

The certificate is self-signed; browser warnings are expected.

### Example application (echo)

http://echo.local:8080

Or via curl:

curl -H "Host: echo.local" http://127.0.0.1:8080

---

## GitOps workflow

This repository follows a strict GitOps model:

- Git is the single source of truth
- No manual kubectl apply for applications
- No direct helm install
- All changes are done via commit and push

Typical workflow:

1. Modify Helm values or manifests in gitops/
2. Commit and push changes
3. Argo CD automatically reconciles the cluster state

---

## Cleanup

To remove the cluster completely:

./scripts/down.sh

This deletes the KIND cluster and all associated resources.

---


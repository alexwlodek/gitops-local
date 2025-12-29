# GitOps Kubernetes Playground (KIND + Argo CD)

Local Kubernetes platform demonstrating a **production-style GitOps workflow** using **KIND** and **Argo CD**.

This project serves as a **reference baseline** for building and operating Kubernetes platforms in a declarative, reproducible way — without relying on cloud infrastructure.

---

## What it demonstrates

- GitOps as the single source of truth
- Declarative cluster and application management
- Argo CD App-of-Apps pattern
- Ingress-based access without port-forwarding
- Clean separation between bootstrap and runtime state
- Local environment closely mirroring production workflows

---

## Architecture (high level)

Host → KIND port mappings → ingress-nginx → Ingress → Service → Pod

Endpoints:
- Argo CD UI → https://argocd.local:8443  
- Example application → http://echo.local:8080  

---

## GitOps workflow

- Desired state defined in Git
- Argo CD continuously reconciles cluster state
- No manual `kubectl apply` or `helm install`
- Changes deployed via commit and push
- Drift automatically detected and corrected

---

## Why this project

This repository is intentionally minimal and stable.
It acts as a **foundation** for larger platform projects, such as:
- CI/CD pipelines
- observability stacks
- secrets management
- migration to managed Kubernetes (EKS/GKE/AKS)

---

**This project represents the platform baseline on which more complex systems can be built.**

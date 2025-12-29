# local-k8s (kind + ingress-nginx)

Local Kubernetes lab on Windows using WSL2 + Docker Desktop + kind.

## What it bootstraps
- kind cluster: 1 control-plane + 2 workers
- ingress-nginx installed via Helm
- demo echo application exposed via Ingress
- local access via `kubectl port-forward` on `localhost:8080`

## Usage
```bash
./scripts/up.sh
# gitops-local
# gitops-local

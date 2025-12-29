#!/bin/bash
set -euo pipefail

if [ -f /tmp/port-forward-ingress.pid ]; then
  PID="$(cat /tmp/port-forward-ingress.pid)"
  if ps -p "$PID" >/dev/null 2>&1; then
    echo "[+] Stopping port-forward (PID $PID)"
    kill "$PID" || true
  fi
  rm -f /tmp/port-forward-ingress.pid
else
  echo "[=] No port-forward PID file found"
fi

# awaryjnie ubij po komendzie
pkill -f "kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller" >/dev/null 2>&1 || true

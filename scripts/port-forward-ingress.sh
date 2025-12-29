#!/bin/bash
set -euo pipefail

NS="ingress-nginx"
SVC="ingress-nginx-controller"
LOCAL_PORT="${LOCAL_PORT:-8080}"   # 80 wymaga sudo, więc domyślnie 8080
REMOTE_PORT=80

echo "[+] Starting port-forward: localhost:${LOCAL_PORT} -> ${NS}/${SVC}:${REMOTE_PORT}"

# ubij wcześniejszy port-forward jeśli działa
pkill -f "kubectl -n ${NS} port-forward svc/${SVC} ${LOCAL_PORT}:${REMOTE_PORT}" >/dev/null 2>&1 || true

# uruchom w tle (nohup) i zapisz PID
nohup kubectl -n "${NS}" port-forward "svc/${SVC}" "${LOCAL_PORT}:${REMOTE_PORT}" \
  >/tmp/port-forward-ingress.log 2>&1 &

echo $! > /tmp/port-forward-ingress.pid
sleep 1

for i in {1..10}; do
  if curl -sS "http://127.0.0.1:${LOCAL_PORT}/" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ps -p "$(cat /tmp/port-forward-ingress.pid)" >/dev/null 2>&1; then
  echo "[=] Port-forward running (PID $(cat /tmp/port-forward-ingress.pid))"
  echo "[=] Test URL: http://127.0.0.1:${LOCAL_PORT}/ (Host: echo.local)"
else
  echo "[!] Port-forward failed. Logs:"
  tail -n 80 /tmp/port-forward-ingress.log || true
  exit 1
fi

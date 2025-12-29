#!/bin/bash
set -euo pipefail

LOCAL_PORT="${LOCAL_PORT:-8080}"
curl -fsS -H "Host: echo.local" "http://127.0.0.1:${LOCAL_PORT}/" | head -c 300 && echo

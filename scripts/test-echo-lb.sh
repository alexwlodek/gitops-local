#!/usr/bin/env bash
set -euo pipefail

# ---- config ----
URL="${URL:-http://127.0.0.1:8080/}"     # port-forward ingress-nginx -> localhost:8080
HOST_HEADER="${HOST_HEADER:-echo.local}" # Ingress host
N="${N:-50}"                             # number of requests
SLEEP_SEC="${SLEEP_SEC:-0}"              # optional delay between requests
NS="${NS:-demo}"
APP_LABEL="${APP_LABEL:-app=echo}"

# ---- helpers ----
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }

need kubectl
need curl
need awk
need sort
need uniq
need grep
need sed

echo "[+] Verifying cluster state"
kubectl -n "$NS" get pods -l "$APP_LABEL" -o wide >/dev/null

# expected pod IPs
mapfile -t EXPECTED_IPS < <(kubectl -n "$NS" get pods -l "$APP_LABEL" -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' | sort -u)

if [[ "${#EXPECTED_IPS[@]}" -eq 0 ]]; then
  echo "[!] No pods found for label: $APP_LABEL in namespace: $NS" >&2
  exit 1
fi

echo "[+] Expected pod IPs (${#EXPECTED_IPS[@]}):"
printf "    - %s\n" "${EXPECTED_IPS[@]}"

echo
echo "[+] Running $N requests against: $URL (Host: $HOST_HEADER)"
echo "    Tip: override with envs: N=200 SLEEP_SEC=0.05 URL=... HOST_HEADER=..."

# associative arrays need bash 4+
declare -A COUNTS
declare -A HOSTNAMES
declare -A UNKNOWN

for ((i=1; i<=N; i++)); do
  # request
  resp="$(curl -sS -H "Host: ${HOST_HEADER}" "${URL}" || true)"

  # Extract pod IP from JSON: "ip":"::ffff:10.244.x.y" OR "ip":"10.244.x.y"
  ip="$(printf '%s' "$resp" | sed -nE 's/.*"ip":"(::ffff:)?([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)".*/\2/p' | head -n1)"

  # Extract pod hostname if present. If not, leave empty.
  hn="$(printf '%s' "$resp" | sed -nE 's/.*"HOSTNAME":"([^"]+)".*/\1/p' | head -n1)"

  if [[ -z "$ip" ]]; then
    echo "[!] Request $i: could not parse pod IP from response" >&2
    echo "    Response snippet: $(printf '%s' "$resp" | head -c 200)..." >&2
    UNKNOWN["<unparsed>"]=$(( ${UNKNOWN["<unparsed>"]:-0} + 1 ))
  else
    COUNTS["$ip"]=$(( ${COUNTS["$ip"]:-0} + 1 ))
    if [[ -n "$hn" ]]; then
      HOSTNAMES["$ip"]="$hn"
    fi
  fi

  if [[ "$SLEEP_SEC" != "0" ]]; then
    sleep "$SLEEP_SEC"
  fi
done

echo
echo "[+] Results (requests per pod IP):"
# print sorted by count desc
{
  for ip in "${!COUNTS[@]}"; do
    echo "${COUNTS[$ip]} $ip"
  done
} | sort -nr | while read -r count ip; do
  hn="${HOSTNAMES[$ip]:-}"
  if [[ -n "$hn" ]]; then
    printf "    %4s  %s  (%s)\n" "$count" "$ip" "$hn"
  else
    printf "    %4s  %s\n" "$count" "$ip"
  fi
done

if [[ "${#UNKNOWN[@]}" -gt 0 ]]; then
  echo
  echo "[!] Unparsed responses: "
  for k in "${!UNKNOWN[@]}"; do
    echo "    ${k}: ${UNKNOWN[$k]}"
  done
fi

echo
echo "[+] Coverage check vs current pods:"
# mark which expected IPs were hit
hit=0
miss=0
for ip in "${EXPECTED_IPS[@]}"; do
  if [[ -n "${COUNTS[$ip]:-}" ]]; then
    echo "    OK  hit $ip (${COUNTS[$ip]} times)"
    hit=$((hit+1))
  else
    echo "    MISS  $ip (0 hits)"
    miss=$((miss+1))
  fi
done

# also detect unexpected IPs (if any)
unexpected=0
for ip in "${!COUNTS[@]}"; do
  if ! printf '%s\n' "${EXPECTED_IPS[@]}" | grep -qx "$ip"; then
    echo "    UNEXPECTED endpoint observed: $ip (${COUNTS[$ip]} times)"
    unexpected=$((unexpected+1))
  fi
done

echo
echo "[=] Summary: hit=$hit miss=$miss unexpected=$unexpected"
if [[ "$miss" -gt 0 ]]; then
  echo "[!] Not all pods were hit. Increase N (e.g. N=200) or check session affinity/stickiness." >&2
  exit 2
fi

echo "[✓] All pods were hit at least once."

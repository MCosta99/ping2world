#!/bin/bash
# ping2world.sh — measure latency to global servers (meter.net server list)
# Usage: ./ping2world.sh [-n samples] [-t timeout] [-p parallel] [-o output.csv] [-f]

# Description: Measure latency to global servers from meter.net server list
# Author: Mattia Costa (AI slop)
# Created: 16/03/2026
# Credits: All credits to meter.net

set -euo pipefail

# ── defaults ────────────────────────────────────────────────────────────────
SAMPLES=3
TIMEOUT=5
PARALLEL=20
OUTFILE=""
FORCE_REFRESH=0
CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/pingworld_servers.json"
CACHE_TTL=3600  # 1 hour in seconds
API_URL="https://www.meter.net/_pub/req/stInit.php?ver=&typ=initformall"

# ── colours ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── usage ────────────────────────────────────────────────────────────────────
usage() {
  echo "Usage: $0 [-n samples] [-t timeout_sec] [-p parallel_jobs] [-o output.csv] [-f]"
  echo "  -n  ping samples per server      (default: $SAMPLES)"
  echo "  -t  connect timeout in seconds   (default: $TIMEOUT)"
  echo "  -p  parallel workers             (default: $PARALLEL)"
  echo "  -o  save results to CSV file"
  echo "  -f  force refresh server list (bypass cache)"
  exit 1
}

while getopts "n:t:p:o:fh" opt; do
  case $opt in
    n) SAMPLES=$OPTARG ;;
    t) TIMEOUT=$OPTARG ;;
    p) PARALLEL=$OPTARG ;;
    o) OUTFILE=$OPTARG ;;
    f) FORCE_REFRESH=1 ;;
    h|*) usage ;;
  esac
done

# ── dependency check ─────────────────────────────────────────────────────────
for cmd in curl jq awk sort; do
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "${RED}Error: '$cmd' is required but not installed.${RESET}"
    [[ "$cmd" == "jq" ]] && echo "  Install with: apt install jq  OR  yum install jq"
    exit 1
  fi
done

# ── fetch server list (with cache) ───────────────────────────────────────────
_cache_valid() {
  [[ -f "$CACHE_FILE" ]] || return 1
  local age=$(( $(date +%s) - $(date -r "$CACHE_FILE" +%s) ))
  (( age < CACHE_TTL ))
}

_fetch_servers() {
  curl -s --max-time 15 \
    -H "Referer: https://www.meter.net/" \
    -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120.0 Safari/537.36" \
    "$API_URL"
}

if [[ "$FORCE_REFRESH" -eq 1 ]] || ! _cache_valid; then
  if [[ "$FORCE_REFRESH" -eq 1 ]]; then
    echo -e "${CYAN}${BOLD}Refreshing server list (cache bypassed)...${RESET}"
  else
    echo -e "${CYAN}${BOLD}Fetching server list from meter.net...${RESET}"
  fi
  mkdir -p "$(dirname "$CACHE_FILE")"
  RAW=$(_fetch_servers) || { echo -e "${RED}Failed to fetch server list.${RESET}"; exit 1; }
  # only cache if response looks valid
  if echo "$RAW" | jq -e '.servers | length > 0' &>/dev/null; then
    echo "$RAW" > "$CACHE_FILE"
  fi
else
  local_age=$(( $(date +%s) - $(date -r "$CACHE_FILE" +%s) ))
  echo -e "${CYAN}${BOLD}Using cached server list${RESET} (${local_age}s old, refresh with -f)"
  RAW=$(< "$CACHE_FILE")
fi

# debug: show raw response if no servers found
_debug_api() { echo "Raw API response (first 300 chars):"; echo "$RAW" | head -c 300; echo; }

# validate JSON
SERVER_COUNT=$(echo "$RAW" | jq '.servers | length' 2>/dev/null) || {
  echo -e "${RED}Unexpected API response format.${RESET}"; exit 1
}

if [[ -z "$SERVER_COUNT" || "$SERVER_COUNT" -eq 0 ]]; then
  echo -e "${RED}No servers found in API response.${RESET}"
  _debug_api
  exit 1
fi

echo -e "Found ${BOLD}${SERVER_COUNT}${RESET} servers. Testing with ${SAMPLES} sample(s) each, ${PARALLEL} workers...\n"

# ── build server list as TSV: hostname<TAB>port<TAB>city<TAB>country<TAB>provider
SERVERS_TSV=$(echo "$RAW" | jq -r '
  .servers[] |
  [.hostname, (.port_https | tostring), .city, .country, .hs_title] |
  @tsv
')

TOTAL=$(echo "$SERVERS_TSV" | wc -l)
TMPDIR_RESULTS=$(mktemp -d)
trap 'rm -rf "$TMPDIR_RESULTS"' EXIT

# ── probe function (exported for xargs subshells) ────────────────────────────
probe_server() {
  local line="$1"
  local samples="$2"
  local timeout="$3"
  local tmpdir="$4"

  local host port city country provider
  host=$(echo "$line"    | cut -f1)
  port=$(echo "$line"    | cut -f2)
  city=$(echo "$line"    | cut -f3)
  country=$(echo "$line" | cut -f4)
  provider=$(echo "$line"| cut -f5)

  local best=99999
  local i
  for ((i=0; i<samples; i++)); do
    local t
    t=$(curl -o /dev/null -s \
      --max-time "$timeout" \
      --connect-timeout "$timeout" \
      -w "%{time_connect}" \
      "https://${host}:${port}/" 2>/dev/null || echo "0")

    # skip zero (failed) results
    if [[ "$t" != "0" && "$t" != "0.000000" ]]; then
      # convert to ms integer for comparison (awk for float math)
      local ms
      ms=$(awk "BEGIN{printf \"%.0f\", $t * 1000}")
      (( ms < best )) && best=$ms
    fi
  done

  # write result: latency_ms<TAB>city<TAB>country<TAB>provider<TAB>host:port
  local outfile="${tmpdir}/${host}_${port}.txt"
  if [[ $best -eq 99999 ]]; then
    printf "999999\t%s\t%s\t%s\t%s:%s\tTIMEOUT\n" \
      "$city" "$country" "$provider" "$host" "$port" > "$outfile"
  else
    printf "%d\t%s\t%s\t%s\t%s:%s\t%d ms\n" \
      "$best" "$city" "$country" "$provider" "$host" "$port" "$best" > "$outfile"
  fi
}

export -f probe_server

# ── run probes in parallel ───────────────────────────────────────────────────
# progress counter via shared temp file
PROGRESS_FILE=$(mktemp)
echo 0 > "$PROGRESS_FILE"

probe_with_progress() {
  probe_server "$1" "$SAMPLES" "$TIMEOUT" "$TMPDIR_RESULTS"
  # atomic increment
  (
    flock 200
    n=$(<"$PROGRESS_FILE")
    echo $((n+1)) > "$PROGRESS_FILE"
    printf "\r  Testing... %d / %d" "$((n+1))" "$TOTAL" >&2
  ) 200>"${PROGRESS_FILE}.lock"
}
export -f probe_with_progress
export SAMPLES TIMEOUT TMPDIR_RESULTS TOTAL PROGRESS_FILE

echo "$SERVERS_TSV" | xargs -P "$PARALLEL" -I{} bash -c 'probe_with_progress "$@"' _ {}
echo  # newline after progress

# ── collect & sort results ───────────────────────────────────────────────────
SORTED=$(cat "$TMPDIR_RESULTS"/*.txt 2>/dev/null | sort -n -k1)

# ── display table ────────────────────────────────────────────────────────────
echo ""
printf "${BOLD}%-5s  %-22s %-20s %-22s %-30s %s${RESET}\n" \
  "Rank" "City" "Country" "Provider" "Host" "Latency"
printf '%s\n' "$(printf '─%.0s' {1..115})"

rank=0
while IFS=$'\t' read -r ms city country provider host latency_str; do
  rank=$((rank+1))
  if [[ "$latency_str" == "TIMEOUT" ]]; then
    color="$RED"
  elif [[ "$ms" -lt 50 ]]; then
    color="$GREEN"
  elif [[ "$ms" -lt 150 ]]; then
    color="$YELLOW"
  else
    color="$RED"
  fi
  printf "${color}%-5d  %-22s %-20s %-22s %-30s %s${RESET}\n" \
    "$rank" "${city:0:21}" "${country:0:19}" "${provider:0:21}" "${host:0:29}" "$latency_str"
done <<< "$SORTED"

echo ""
echo -e "${BOLD}Total servers tested: ${rank}${RESET}"

# ── optional CSV export ──────────────────────────────────────────────────────
if [[ -n "$OUTFILE" ]]; then
  echo "Rank,City,Country,Provider,Host,Latency_ms" > "$OUTFILE"
  rank=0
  while IFS=$'\t' read -r ms city country provider host latency_str; do
    rank=$((rank+1))
    local_ms="$ms"
    [[ "$latency_str" == "TIMEOUT" ]] && local_ms="timeout"
    printf '%d,"%s","%s","%s","%s",%s\n' \
      "$rank" "$city" "$country" "$provider" "$host" "$local_ms" >> "$OUTFILE"
  done <<< "$SORTED"
  echo -e "${GREEN}Results saved to: ${OUTFILE}${RESET}"
fi

rm -f "$PROGRESS_FILE" "${PROGRESS_FILE}.lock"

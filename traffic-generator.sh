#!/usr/bin/env bash
#
# traffic-generator.sh
# Generates continuous or burst HTTP traffic to the OpenTelemetry demo app.
#

set -euo pipefail

# Target URL: Default to Node 5 private IP, or override via argument/environment
# Example usage: ./traffic-generator.sh http://<NODE_5_PUBLIC_OR_PRIVATE_IP>:8000
TARGET_HOST="${1:-${DEMO_APP_URL:-http://10.0.1.50:8000}}"

echo "=========================================================="
echo " Starting OpenTelemetry Traffic Generator"
echo " Target Host: ${TARGET_HOST}"
echo " Endpoints:   /order (normal), /error (500), /notfound (404)"
echo " Press [Ctrl+C] to stop."
echo "=========================================================="

# Track request totals
count_200=0
count_500=0
count_404=0

# Clean exit handler
trap 'echo -e "\nTraffic stopped. Summary: 200 OK: ${count_200} | 500 Error: ${count_500} | 404 Not Found: ${count_404}"; exit 0' INT TERM

while true; do
  # Generate a random number 1-100 to determine endpoint distribution:
  # - 75% normal orders (/order)
  # - 15% simulated server errors (/error)
  # - 10% not found routes (/missing)
  rand_val=$(( RANDOM % 100 + 1 ))

  if [ "${rand_val}" -le 75 ]; then
    endpoint="/order"
  elif [ "${rand_val}" -le 90 ]; then
    endpoint="/error"
  else
    endpoint="/missing-route-$(( RANDOM % 10 ))"
  fi

  url="${TARGET_HOST}${endpoint}"
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")

  # Fire request and capture HTTP status code
  status_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "${url}" || echo "000")

  case "${status_code}" in
    200)
      count_200=$(( count_200 + 1 ))
      echo -e "[${timestamp}] \033[32m${status_code} OK\033[0m          --> GET ${endpoint}"
      ;;
    500)
      count_500=$(( count_500 + 1 ))
      echo -e "[${timestamp}] \033[31m${status_code} SERVER ERROR\033[0m --> GET ${endpoint}"
      ;;
    404)
      count_404=$(( count_404 + 1 ))
      echo -e "[${timestamp}] \033[33m${status_code} NOT FOUND\033[0m    --> GET ${endpoint}"
      ;;
    000)
      echo -e "[${timestamp}] \033[41;37m CONNECTION FAILED \033[0m --> Target unreachable at ${url}"
      ;;
    *)
      echo -e "[${timestamp}] ${status_code}              --> GET ${endpoint}"
      ;;
  esac

  # Random sleep between 0.1s and 0.5s to simulate realistic user arrival
  sleep_interval="0.$(( RANDOM % 5 + 1 ))"
  sleep "${sleep_interval}"
done
#!/usr/bin/env bash
# Tear down everything this project created.
set -uo pipefail
cd "$(dirname "$0")/.."

echo "--- compose stack ---"
docker compose down                       # add -v to also delete the volume

echo "--- manual (Task 2) containers ---"
docker rm -f collector-manual dashboard-manual 2>/dev/null
docker network rm monitoring-net-manual   2>/dev/null
docker volume  rm metrics-data-manual     2>/dev/null

echo "Remaining project resources:"
docker ps -a  | grep -E 'collector|dashboard' || echo "  no containers"
docker volume ls | grep metrics-data              || echo "  no volumes"

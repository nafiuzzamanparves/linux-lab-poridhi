#!/usr/bin/env bash
# Task 2 + Task 3 — build, network, volume and run WITHOUT Compose.
# Proves each Docker primitive individually before compose.yaml wraps them up.
set -euo pipefail
cd "$(dirname "$0")/.."

NET=monitoring-net-manual
VOL=metrics-data-manual

echo "### 1. Pull and inspect the base NGINX image"
docker pull nginx:1.27-alpine
docker images | grep -E 'REPOSITORY|nginx'

echo
echo "### 2. Build both application images"
docker build -t monitoring/collector:1.0 ./collector
docker build -t monitoring/dashboard:1.0 ./dashboard
docker images | grep -E 'REPOSITORY|monitoring/'

echo
echo "### 3. Create the network and the volume"
docker network create --driver bridge "$NET" 2>/dev/null || echo "network $NET already exists"
docker volume create "$VOL"           2>/dev/null || echo "volume  $VOL already exists"
docker network ls
docker volume ls

echo
echo "### 4. Run the collector (volume attached, no published port)"
docker rm -f collector-manual >/dev/null 2>&1 || true
docker run -d \
  --name collector-manual \
  --network "$NET" \
  --network-alias collector \
  -v "$VOL":/data \
  --restart unless-stopped \
  monitoring/collector:1.0

echo
echo "### 5. Run the dashboard (host 9090 -> container 80)"
docker rm -f dashboard-manual >/dev/null 2>&1 || true
docker run -d \
  --name dashboard-manual \
  --network "$NET" \
  -p 9090:80 \
  --restart unless-stopped \
  monitoring/dashboard:1.0

sleep 3
echo
echo "### 6. Verify"
docker ps
echo "--- network members (service names, not IPs) ---"
docker network inspect "$NET" --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'
echo "--- volume mountpoint ---"
docker volume inspect "$VOL" --format '{{.Name}} -> {{.Mountpoint}}'
echo "--- collector reached from INSIDE the dashboard container, by name ---"
docker exec dashboard-manual wget -qO- http://collector:6000/status
echo "--- dashboard reached from the host ---"
curl -s -o /dev/null -w 'GET / -> HTTP %{http_code}\n' http://localhost:9090/
curl -s http://localhost:9090/api/status

echo
echo "Done. Tear down with: scripts/04-cleanup.sh"

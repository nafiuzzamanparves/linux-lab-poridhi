#!/usr/bin/env bash
# Task 4 + Task 5 — verify and monitor the Compose deployment.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== docker compose ps ==="
docker compose ps

echo
echo "=== docker images ==="
docker images | grep -E 'REPOSITORY|monitoring/|nginx'

echo
echo "=== docker network ls / inspect ==="
docker network ls | grep -E 'NETWORK|monitoring'
docker network inspect monitoring-app_monitoring-net \
  --format 'network: {{.Name}} ({{.Driver}}){{"\n"}}{{range .Containers}}  {{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'

echo
echo "=== docker volume ls / inspect ==="
docker volume ls | grep -E 'DRIVER|metrics-data'
docker volume inspect monitoring-app_metrics-data \
  --format '{{.Name}} driver={{.Driver}} mountpoint={{.Mountpoint}}'

echo
echo "=== service-name DNS: dashboard -> collector ==="
docker exec dashboard getent hosts collector || true
docker exec dashboard wget -qO- http://collector:6000/status

echo
echo "=== curl from the host: dashboard on 9090 ==="
curl -s -o /dev/null -w 'GET /            -> HTTP %{http_code}\n' http://localhost:9090/
curl -s -o /dev/null -w 'GET /api/status  -> HTTP %{http_code}\n' http://localhost:9090/api/status
curl -s http://localhost:9090/api/status

echo
echo "=== persisted samples on the volume ==="
docker exec collector sh -c 'wc -l < /data/metrics.log' | sed 's/^/lines in \/data\/metrics.log: /'
docker exec collector sh -c 'tail -1 /data/metrics.log'

echo
echo "=== resource usage (docker stats, one shot) ==="
docker stats --no-stream

echo
echo "=== recent logs ==="
docker compose logs --tail 10

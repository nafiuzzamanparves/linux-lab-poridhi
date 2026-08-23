# Milestone 1 — Docker & Linux Project

A two-service monitoring application: an **NGINX dashboard** on host port `9090` that talks to a
**metrics collector** on port `6000` over a Docker bridge network, with collected samples persisted
to a Docker volume.

```
                    User / Browser
                          │
                        :9090
                          ▼
                  ┌──────────────┐
                  │   Dashboard  │   nginx:1.27-alpine
                  │    NGINX     │   /api/ ──► http://collector:6000
                  │     :80      │
                  └──────┬───────┘
                         │
              monitoring-net (bridge)
                         │
                  ┌──────▼───────┐
                  │   Metrics    │   python:3.12-alpine
                  │  Collector   │   /status /metrics /history
                  │     :6000    │
                  └──────┬───────┘
                         │
                    metrics-data  ──►  /data/metrics.log
```

## Quick start

```bash
docker compose up -d --build
docker compose ps
curl http://localhost:9090/api/status
```

Then open `http://<server-ip>:9090` in a browser.

## Layout

```
linux-lab-poridhi/
├── compose.yaml                 # Task 4 — whole stack in one file
├── README.md
├── dashboard/
│   ├── Dockerfile               # nginx:1.27-alpine
│   ├── nginx.conf               # static site + /api/ reverse proxy to collector
│   └── index.html               # live metrics dashboard
├── collector/
│   ├── Dockerfile               # python:3.12-alpine, EXPOSE 6000
│   ├── app.py                   # stdlib HTTP API, no pip dependencies
│   └── .dockerignore
├── scripts/
│   ├── 01-linux-setup.sh        # Task 1 — uname / ip addr / df -h / ls -l / ss -tulnp
│   ├── 02-manual-docker.sh      # Task 2+3 — build, network, volume, docker run (no Compose)
│   ├── 03-verify.sh             # Task 4+5 — verification and monitoring pass
│   └── 04-cleanup.sh            # tear everything down
└── docs/
    ├── verification-output.txt  # captured output of 03-verify.sh
    └── linux-setup-output.txt   # captured output of 01-linux-setup.sh
```

---

## Task 1 — Linux setup

```bash
scripts/01-linux-setup.sh
```

Runs `uname -a`, `ip addr`, `df -h`, `free -h`, `ls -lR`, `ss -tulnp`. The dashboard placeholder
(`dashboard/index.html`) and the metrics API with its `/status` endpoint (`collector/app.py`) are
the two application files created in this step.

`ip addr` gives the server IP used to reach the dashboard at `http://<server-ip>:9090`.

## Task 2 — Docker basics, images, networking, storage

```bash
scripts/02-manual-docker.sh
```

Does each primitive on its own, before Compose hides them:

| Step | Command |
|---|---|
| Pull the base image | `docker pull nginx:1.27-alpine` |
| Build both images | `docker build -t monitoring/collector:1.0 ./collector` |
| | `docker build -t monitoring/dashboard:1.0 ./dashboard` |
| Create the network | `docker network create --driver bridge monitoring-net-manual` |
| Create the volume | `docker volume create metrics-data-manual` |
| Run the collector | `docker run -d --name collector-manual --network monitoring-net-manual --network-alias collector -v metrics-data-manual:/data --restart unless-stopped monitoring/collector:1.0` |
| Run the dashboard | `docker run -d --name dashboard-manual --network monitoring-net-manual -p 9090:80 --restart unless-stopped monitoring/dashboard:1.0` |
| Verify | `docker images`, `docker ps`, `docker network inspect`, `docker volume inspect` |

`--network-alias collector` is what lets the dashboard reach the collector as `http://collector:6000`
even though the container is named `collector-manual`. **No container IP appears anywhere in the
configuration** — `dashboard/nginx.conf` proxies to the service name and lets Docker's embedded DNS
(`127.0.0.11`) resolve it.

## Task 3 — Dockerize

* `dashboard/Dockerfile` — `FROM nginx:1.27-alpine`, copies `nginx.conf` and `index.html`, exposes 80.
* `collector/Dockerfile` — `FROM python:3.12-alpine`, exposes 6000, `CMD ["python", "app.py"]`.

Both have a `HEALTHCHECK`, so `docker ps` reports `(healthy)` rather than just `Up` — a cheap way to
tell "the container is running" apart from "the app inside it is answering".

Collector endpoints:

| Endpoint | Purpose |
|---|---|
| `GET /status` | health, port, uptime, number of samples stored on the volume |
| `GET /metrics` | current CPU load / memory / disk snapshot, also appended to the volume |
| `GET /history` | last 20 persisted samples |

Verification:

```bash
# dashboard from the host
curl -i http://localhost:9090/

# collector through the dashboard's reverse proxy
curl http://localhost:9090/api/status

# collector directly, from inside the dashboard container, by service name
docker exec dashboard wget -qO- http://collector:6000/status
```

## Task 4 — Docker Compose

`compose.yaml` covers every required element:

| Requirement | Where |
|---|---|
| Dashboard service | `services.dashboard`, built from `./dashboard` |
| Collector service | `services.collector`, built from `./collector` |
| Port mapping | `ports: ["9090:80"]` on the dashboard |
| Docker network | `networks.monitoring-net`, driver `bridge`, both services joined |
| Docker volume | `volumes.metrics-data` mounted at `/data` in the collector |
| Restart policy | `restart: unless-stopped` on both services |

```bash
docker compose up -d --build
docker compose ps
docker compose logs
```

The collector's port is deliberately **not** published. Only the dashboard needs it, and it reaches
it over the internal network — so the metrics API is not exposed to the outside world. Publishing it
is a two-line uncomment in `compose.yaml` if you want to `curl` it directly from the host.

Compose prefixes its resources with the project name, so the real names are
`monitoring-app_monitoring-net` and `monitoring-app_metrics-data`.

### Verified output

```
NAME        IMAGE                      SERVICE     STATUS                    PORTS
collector   monitoring/collector:1.0   collector   Up 12 seconds (healthy)   6000/tcp
dashboard   monitoring/dashboard:1.0   dashboard   Up 12 seconds (healthy)   0.0.0.0:9090->80/tcp
```

Full captured run: [docs/verification-output.txt](docs/verification-output.txt).

### Volume persistence, proved

```bash
curl -s http://localhost:9090/api/metrics >/dev/null   # collect a few samples
docker exec collector sh -c 'wc -l < /data/metrics.log'   # -> 4
docker compose down                                    # containers destroyed, volume kept
docker volume ls | grep metrics-data                   # -> monitoring-app_metrics-data
docker compose up -d
docker exec collector sh -c 'wc -l < /data/metrics.log'   # -> 5, history survived
```

## Task 5 — Monitoring & troubleshooting

```bash
scripts/03-verify.sh
```

Covers `docker compose ps`, `docker images`, `docker network inspect`, `docker volume inspect`,
service-name DNS resolution, `curl` against both the dashboard and the proxied collector, the
sample count on the volume, `docker stats`, and `docker compose logs`.

### Problem actually hit and fixed: `/api/status` returned the wrong payload

**Symptom.** `curl http://localhost:9090/api/status` returned HTTP 200 — but with the collector's
*root* response (the endpoint index) instead of the status payload. A 200 made it look like it was
working; only reading the body showed it wasn't.

**Which command found it.** `curl -s http://localhost:9090/api/status` compared against
`docker exec dashboard wget -qO- http://collector:6000/status`. The direct call returned the correct
status JSON, the proxied one didn't — so the collector was fine and the fault was in the proxy hop.
`docker compose logs collector` confirmed it: the collector was logging `"GET / HTTP/1.0"`, not
`"GET /status"`. The dashboard was asking for the wrong path.

**Cause.** The original config was:

```nginx
set $collector http://collector:6000;
proxy_pass $collector/;
```

When `proxy_pass` contains a **variable**, NGINX does not do its normal trick of stripping the
matched `location` prefix and appending the rest. The literal URI after the variable — `/` — was
sent for every request, so `/api/status` and `/api/metrics` both arrived as `/`.

**Fix.** Rewrite the path explicitly, then `proxy_pass` with no URI part so the rewritten URI is
used:

```nginx
set $collector http://collector:6000;
rewrite ^/api/?(.*)$ /$1 break;
proxy_pass $collector;
```

After `docker build` + re-run, `/api/status` and `/api/metrics` both returned their correct payloads.

The variable is worth keeping despite the extra line: with a literal `proxy_pass http://collector:6000/`,
NGINX resolves the hostname at config-load time and **exits** if the collector container isn't up
yet. With the variable plus `resolver 127.0.0.11`, resolution happens per request, so the dashboard
starts regardless of ordering and simply returns 502 until the collector answers.

### Other failure modes and how to read them

| Symptom | Cause | How to find it | Fix |
|---|---|---|---|
| `/api/*` → **502 Bad Gateway** | collector down or crashed | `docker compose ps` (collector not `healthy`), `docker compose logs collector` | `docker compose up -d collector` |
| `/api/*` → **502**, log says `no resolver defined` or `host not found` | dashboard not on the same network as the collector | `docker network inspect monitoring-app_monitoring-net` — only one container listed | put both services on `monitoring-net` in `compose.yaml` |
| `docker compose up` → `port is already allocated` | something else holds host 9090 | `ss -tulnp \| grep 9090` (`lsof -nP -iTCP:9090` on macOS) | stop the other process or change the host side of `9090:80` |
| Metrics reset to zero after a redeploy | volume removed | `docker volume ls` — `metrics-data` missing | don't use `docker compose down -v`; `down` alone keeps the volume |
| Dashboard loads but tiles show `–` and "collector unreachable" | browser can reach NGINX, NGINX can't reach the collector | browser devtools network tab, then `docker exec dashboard wget -qO- http://collector:6000/status` | same as the 502 rows above |

One Linux detail worth knowing while debugging: `docker exec collector kill -9 1` **does nothing**.
PID 1 in a PID namespace is protected from signals sent from inside that namespace unless the
process installed a handler for them, so you cannot kill the app that way. Use `docker kill` /
`docker stop` from the host instead — but note those count as an *explicit* stop, so
`unless-stopped` will not bring the container back. To see the restart policy actually fire, the
process has to die on its own.

---

## Short questions

**1. What is the difference between a Docker image and a container?**

An image is the read-only package — filesystem layers plus metadata (entrypoint, env, exposed
ports). A container is a running instance of an image: the image's layers plus a writable layer and
its own process, network namespace, and lifecycle. One image, many containers. Here
`monitoring/collector:1.0` is the image; `collector` is the container built from it. Rebuild the
image and nothing changes until you recreate the container — which is exactly why `docker compose
up -d --build` exists.

**2. What does `9090:80` mean?**

`HOST:CONTAINER`. Docker publishes container port 80 on host port 9090, so traffic to
`http://<server-ip>:9090` is forwarded to NGINX listening on 80 inside the container. The container
port stays 80 — only the host-side entry point changes. Nothing inside the container knows or cares
about 9090.

**3. Why do containers need a Docker network?**

For discovery and isolation. On a user-defined bridge network, Docker runs an embedded DNS server at
`127.0.0.11` that resolves **service and container names** to current IPs, so the dashboard can use
`http://collector:6000` and keep working after the collector is recreated with a different IP.
Hard-coding `172.18.0.2` would break on the next restart. The network is also a boundary: only
containers on `monitoring-net` can reach the collector, and since its port isn't published, nothing
outside the network can.

**4. Why do we use Docker volumes?**

A container's writable layer dies with the container. A volume is storage managed by Docker outside
that layer, so data outlives `docker rm` and container recreation — proved above: `docker compose
down` then `up` and `/data/metrics.log` still held every earlier sample. Volumes also perform better
than writing to the container layer and can be backed up or inspected on their own
(`docker volume inspect`).

**5. What problem does Docker Compose solve?**

It replaces a growing pile of imperative `docker network create` / `docker volume create` /
`docker run -d --name … --network … -v … -p …` commands with one declarative file that is
version-controlled, reviewable, and reproducible. It creates the network and volume, builds images,
starts services in dependency order, and gives one lifecycle handle for the whole stack
(`up`, `down`, `ps`, `logs`, `restart`). Compare `scripts/02-manual-docker.sh` — around 20
commands and easy to get wrong — with `docker compose up -d`.

## Bonus — restart policy

Both services use:

```yaml
restart: unless-stopped
```

Docker restarts the container automatically if it exits for any reason — a crash, a non-zero exit,
an OOM kill — and also brings it back when the Docker daemon itself restarts (so the app survives a
server reboot). The one exception is in the name: if *you* stopped it (`docker stop`), it stays
stopped and does not come back when the daemon restarts.

The options, briefly:

| Policy | Behaviour |
|---|---|
| `no` (default) | never restarted |
| `on-failure[:N]` | restarted only on non-zero exit, optionally capped at N attempts |
| `always` | always restarted, *including* after you manually stopped it and the daemon restarts |
| `unless-stopped` | like `always`, but respects a manual stop |

`unless-stopped` is the right pick for a long-running service like this: it self-heals from crashes
and reboots, but does not fight an operator who deliberately took it down for maintenance.

Verified with a container that crashes on its own:

```bash
docker run -d --name restart-demo --restart unless-stopped alpine sh -c 'sleep 2; exit 1'
docker inspect restart-demo --format '{{.RestartCount}} {{.State.Status}}'
#   6s  -> 2 running
#  12s  -> 5 restarting
#  18s  -> 6 restarting        # Docker keeps bringing it back, with backoff
```

## Submission checklist

Screenshots to capture from the lab (after `docker compose up -d`):

| Screenshot | Command / URL |
|---|---|
| Working dashboard | `http://<server-ip>:9090` in a browser |
| Compose status | `docker compose ps` |
| Images | `docker images` |
| Network | `docker network inspect monitoring-app_monitoring-net` |
| Volume | `docker volume inspect monitoring-app_metrics-data` |

Bonus evidence: `docker compose ps` showing `(healthy)`, and
`docker inspect collector --format '{{.HostConfig.RestartPolicy.Name}}'` → `unless-stopped`.

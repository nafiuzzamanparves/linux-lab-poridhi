#!/usr/bin/env python3
"""Metrics Collector.

Small stdlib-only HTTP service that exposes system metrics for the dashboard.
Listens on 0.0.0.0:6000 and appends every collected sample to a file on the
Docker volume mounted at /data, so history survives container restarts.

Endpoints:
  GET /status   -> service health + uptime + sample count
  GET /metrics  -> current cpu / memory / disk snapshot (also persisted)
  GET /history  -> last N persisted samples
"""

import json
import os
import shutil
import socket
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("COLLECTOR_PORT", "6000"))
DATA_DIR = os.environ.get("DATA_DIR", "/data")
METRICS_LOG = os.path.join(DATA_DIR, "metrics.log")
STARTED_AT = time.time()


def _read_first_line(path):
    try:
        with open(path) as fh:
            return fh.readline().strip()
    except OSError:
        return ""


def cpu_load():
    """Load average from /proc/loadavg (Linux). Falls back to os.getloadavg()."""
    line = _read_first_line("/proc/loadavg")
    if line:
        parts = line.split()
        return {"1m": float(parts[0]), "5m": float(parts[1]), "15m": float(parts[2])}
    one, five, fifteen = os.getloadavg()
    return {"1m": one, "5m": five, "15m": fifteen}


def memory():
    """Memory totals in MB, parsed from /proc/meminfo."""
    info = {}
    try:
        with open("/proc/meminfo") as fh:
            for line in fh:
                key, _, rest = line.partition(":")
                info[key] = int(rest.split()[0])  # kB
    except OSError:
        return {}
    total = info.get("MemTotal", 0) / 1024
    available = info.get("MemAvailable", 0) / 1024
    used = total - available
    return {
        "total_mb": round(total, 1),
        "used_mb": round(used, 1),
        "available_mb": round(available, 1),
        "used_percent": round((used / total) * 100, 1) if total else 0.0,
    }


def disk(path="/"):
    total, used, free = shutil.disk_usage(path)
    gb = 1024 ** 3
    return {
        "total_gb": round(total / gb, 2),
        "used_gb": round(used / gb, 2),
        "free_gb": round(free / gb, 2),
        "used_percent": round((used / total) * 100, 1) if total else 0.0,
    }


def sample_count():
    try:
        with open(METRICS_LOG) as fh:
            return sum(1 for _ in fh)
    except OSError:
        return 0


def collect():
    return {
        "collected_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "host": socket.gethostname(),
        "cpu_load": cpu_load(),
        "memory": memory(),
        "disk": disk("/"),
    }


def persist(sample):
    """Append one JSON sample to the volume. Never fail the request on IO errors."""
    try:
        os.makedirs(DATA_DIR, exist_ok=True)
        with open(METRICS_LOG, "a") as fh:
            fh.write(json.dumps(sample) + "\n")
        return True
    except OSError as exc:
        print(f"[collector] could not persist sample: {exc}", flush=True)
        return False


def history(limit=20):
    try:
        with open(METRICS_LOG) as fh:
            lines = fh.readlines()[-limit:]
    except OSError:
        return []
    out = []
    for line in lines:
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


class Handler(BaseHTTPRequestHandler):
    server_version = "MetricsCollector/1.0"

    def _send(self, payload, code=200):
        body = json.dumps(payload, indent=2).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        route = self.path.split("?")[0].rstrip("/") or "/"

        if route == "/status":
            self._send({
                "service": "metrics-collector",
                "status": "healthy",
                "port": PORT,
                "host": socket.gethostname(),
                "uptime_seconds": round(time.time() - STARTED_AT, 1),
                "data_dir": DATA_DIR,
                "samples_stored": sample_count(),
            })
        elif route == "/metrics":
            sample = collect()
            sample["persisted"] = persist(sample)
            self._send(sample)
        elif route == "/history":
            self._send({"samples": history()})
        elif route == "/":
            self._send({
                "service": "metrics-collector",
                "endpoints": ["/status", "/metrics", "/history"],
            })
        else:
            self._send({"error": "not found", "path": self.path}, code=404)

    def log_message(self, fmt, *args):
        # Structured-ish log line so `docker logs` / `docker compose logs` is readable.
        print(f"[collector] {self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    persist(collect())  # one sample at boot, proves the volume is writable
    print(f"[collector] listening on 0.0.0.0:{PORT}, data dir {DATA_DIR}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()

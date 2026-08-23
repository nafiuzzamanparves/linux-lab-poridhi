#!/usr/bin/env bash
# Task 1 — Linux environment checks
set -euo pipefail

echo "=== Kernel / OS ==="
uname -a

echo
echo "=== IP addresses ==="
if command -v ip >/dev/null 2>&1; then
  ip addr show | grep -E '^[0-9]+:|inet '
else
  ifconfig | grep -E '^[a-z0-9]+:|inet '     # macOS fallback
fi

echo
echo "=== Disk space ==="
df -h

echo
echo "=== Memory ==="
free -h 2>/dev/null || vm_stat | head -6

echo
echo "=== Project files and permissions ==="
ls -lR "$(dirname "$0")/.."

echo
echo "=== Listening sockets ==="
if command -v ss >/dev/null 2>&1; then
  ss -tulnp
else
  netstat -an | grep LISTEN | head -20      # macOS fallback
fi

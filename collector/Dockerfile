# Metrics Collector — stdlib-only Python service on port 6000
FROM python:3.12-alpine

# Where the Docker volume gets mounted; the app appends samples here.
ENV COLLECTOR_PORT=6000 \
    DATA_DIR=/data \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY app.py .

# Created up front so the container still runs when no volume is attached.
RUN mkdir -p /data

EXPOSE 6000

# Container-level health check, visible in `docker ps` as (healthy).
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://127.0.0.1:6000/status >/dev/null || exit 1

CMD ["python", "app.py"]

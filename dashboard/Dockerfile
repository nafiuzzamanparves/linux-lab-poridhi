# Dashboard — static metrics page served by NGINX on port 80
FROM nginx:1.27-alpine

# Reverse-proxy config: /api/ -> http://collector:6000 over the Docker network
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://127.0.0.1/healthz >/dev/null || exit 1

# nginx:alpine's own entrypoint/CMD already runs nginx in the foreground.

# ─── Stage 1: Build the Instana Steampipe plugin ────────────────────────────
# plugin-src additional_context points to ../steampipe-plugin-instana (see docker-compose.yml)
FROM golang:1.24-alpine AS builder
WORKDIR /build
COPY --from=plugin-src . .
RUN CGO_ENABLED=0 GOOS=linux go build -tags netgo -o steampipe-plugin-instana.plugin .

# ─── Stage 2: Steampipe runtime ──────────────────────────────────────────────
FROM ghcr.io/devops-ia/steampipe:v2.4.1

USER root
RUN apt-get update && apt-get install -y --no-install-recommends gettext-base \
    && rm -rf /var/lib/apt/lists/*

USER steampipe

# Copy the compiled instana plugin binary into the plugin directory
COPY --from=builder --chown=steampipe:steampipe \
    /build/steampipe-plugin-instana.plugin \
    /home/steampipe/.steampipe/plugins/hub.steampipe.io/plugins/hashicorp/instana@latest/steampipe-plugin-instana.plugin

# Version manifest — tells Steampipe the plugin is locally managed
COPY --chown=steampipe:steampipe \
    plugins/instana/version.json \
    /home/steampipe/.steampipe/plugins/hub.steampipe.io/plugins/hashicorp/instana@latest/version.json

# Connection config — plugin reads INSTANA_API_TOKEN / INSTANA_ENDPOINT_URL from env
COPY --from=plugin-src --chown=steampipe:steampipe \
    config/instana.spc \
    /home/steampipe/.steampipe/config/instana.spc


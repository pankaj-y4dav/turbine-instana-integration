FROM ghcr.io/devops-ia/steampipe:v2.4.1

USER root
RUN apt update && apt install -y gettext-base

ARG PLUGINS
USER steampipe
RUN steampipe plugin install ${PLUGINS}

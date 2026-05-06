#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ -f "$ENV_FILE" ]]; then
    set -o allexport
    source "$ENV_FILE"
    set +o allexport
fi

SQL_FILE="${1:-$SCRIPT_DIR/test.sql}"

envsubst < "$SQL_FILE" | steampipe query

#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ -f "$ENV_FILE" ]]; then
    set -o allexport
    source "$ENV_FILE"
    set +o allexport
fi

SQL_FILE="${1:-$SCRIPT_DIR/instana_native.sql}"

# steampipe query does not support multiple statements in a single file.
# Expand env vars, split on semicolons, write each statement to its own
# temp file, and run steampipe query <file> individually.
TMPDIR=$(mktemp -d /tmp/steampipe_query_XXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

envsubst < "$SQL_FILE" > "$TMPDIR/expanded.sql"

# Split on semicolons using awk, writing each statement to a numbered file.
awk -v dir="$TMPDIR" '
  { buf = buf $0 "\n" }
  /;[[:space:]]*$/ {
    sub(/;[[:space:]]*\n$/, "\n", buf)
    if (buf ~ /[^[:space:]]/) {
      n++
      fname = dir "/stmt_" n ".sql"
      print buf > fname
      close(fname)
    }
    buf = ""
  }
' "$TMPDIR/expanded.sql"

for f in "$TMPDIR"/stmt_*.sql; do
    cat "$f"
    steampipe query "$f"
done

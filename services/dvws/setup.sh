#!/usr/bin/env bash

# Built-in setup for DVWS.
# Expects BASE_DIR, ensure_dir, and write_env_port from the main script.
setup_dvws_impl() {
  local dir="$BASE_DIR/dvws"
  ensure_dir "$dir"
  write_env_port "$dir" DVWS_PORT 8087
  cat >"$dir/docker-compose.yml" <<'EOF'
services:
  dvws:
    image: cyrivs89/web-dvws
    ports:
      - "127.0.0.1:${DVWS_PORT:-8087}:80"
    restart: unless-stopped
EOF
}

#!/usr/bin/env bash

# Built-in setup for WebGoat.
# Expects BASE_DIR, ensure_dir, and write_env_port from the main script.
setup_webgoat_impl() {
  local dir="$BASE_DIR/webgoat"
  ensure_dir "$dir"
  write_env_port "$dir" WEBGOAT_PORT 8080
  cat >"$dir/docker-compose.yml" <<'EOF'
services:
  webgoat:
    image: webgoat/webgoat
    ports:
      - "${WEBGOAT_PORT:-8080}:8080"
    restart: unless-stopped
EOF
}

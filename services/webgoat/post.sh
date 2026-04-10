#!/usr/bin/env bash

# Post-setup for WebGoat.
# Expects BASE_DIR, ensure_dir, and log helpers from the main script.
webgoat_post_impl() {
  local dir="$BASE_DIR/webgoat"
  ensure_dir "$dir"
  cat >"$dir/docker-compose.override.yml" <<'EOF'
services:
  webgoat:
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:8080/WebGoat/actuator/health >/dev/null 2>&1 || busybox wget -qO- http://127.0.0.1:8080/WebGoat/actuator/health >/dev/null 2>&1 || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 45s
EOF
}

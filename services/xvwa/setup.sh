#!/usr/bin/env bash

# Built-in setup for XVWA.
# Expects BASE_DIR, ensure_dir, and write_env_port from the main script.
setup_xvwa_impl() {
  local dir="$BASE_DIR/xvwa"
  ensure_dir "$dir"
  write_env_port "$dir" XVWA_PORT 8085
  # Ensure a valid image is set via .env (default to bitnetsecdave/xvwa - v2 manifest)
  if grep -q '^IMAGE_XVWA=' "$dir/.env" 2>/dev/null; then
    sed -i 's/^IMAGE_XVWA=.*/IMAGE_XVWA=bitnetsecdave\/xvwa/' "$dir/.env"
  else
    echo 'IMAGE_XVWA=bitnetsecdave/xvwa' >> "$dir/.env"
  fi
  cat >"$dir/docker-compose.yml" <<'EOF'
services:
  xvwa:
    image: ${IMAGE_XVWA}
    ports:
      - "${XVWA_PORT:-8085}:80"
    restart: unless-stopped
EOF
}

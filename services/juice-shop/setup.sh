#!/usr/bin/env bash

# Source-based setup for Juice Shop.
# Expects BASE_DIR, ensure_dir, and write_env_port from the main script.
juice_shop_setup_impl() {
  local dir="$BASE_DIR/juice-shop"
  ensure_dir "$dir"
  write_env_port "$dir" JUICESHOP_PORT 3000

  local env_file="$dir/.env"
  touch "$env_file"
  if grep -q '^JUICESHOP_IMAGE=' "$env_file"; then
    sed -i 's|^JUICESHOP_IMAGE=.*|JUICESHOP_IMAGE=juice-shop-local|' "$env_file"
  else
    echo 'JUICESHOP_IMAGE=juice-shop-local' >> "$env_file"
  fi

  cat >"$dir/docker-compose.yml" <<'EOF'
services:
  juice-shop:
    image: ${JUICESHOP_IMAGE:-juice-shop-local}
    build:
      context: .
    ports:
      - "${JUICESHOP_PORT:-3000}:3000"
    restart: unless-stopped
EOF

  touch "$dir/.allow_build"
}

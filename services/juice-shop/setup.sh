#!/usr/bin/env bash

# Built-in setup for Juice Shop.
# Expects BASE_DIR, ensure_dir, and write_env_port from the main script.
setup_juice_shop_impl() {
  local dir="$BASE_DIR/juice-shop"
  ensure_dir "$dir"
  write_env_port "$dir" JUICESHOP_PORT 3000
  cat >"$dir/docker-compose.yml" <<'EOF'
services:
  juice-shop:
    image: bkimminich/juice-shop
    ports:
      - "${JUICESHOP_PORT:-3000}:3000"
    restart: unless-stopped
EOF
}

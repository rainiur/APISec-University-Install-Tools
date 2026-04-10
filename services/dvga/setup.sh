#!/usr/bin/env bash

# Built-in setup for DVGA.
# Expects BASE_DIR, write_env_port, and log from the main script.
setup_dvga_impl() {
  local dir="$BASE_DIR/dvga"
  if [[ ! -f "$dir/Dockerfile" ]]; then
    log INFO "Cloning DVGA (blackhatgraphql branch)"
    git clone -b blackhatgraphql https://github.com/dolevf/Damn-Vulnerable-GraphQL-Application.git "$dir"
    sed -i 's#/opt/dvga#/opt/lab/dvga#g' "$dir/Dockerfile"
  fi
  write_env_port "$dir" DVGA_PORT 5013
  cat >"$dir/docker-compose.yml" <<EOF
services:
  dvga:
    build:
      context: $dir
      dockerfile: Dockerfile
    image: dvga
    container_name: dvga
    ports:
      - "${DVGA_PORT:-5013}:5013"
    environment:
      - WEB_HOST=0.0.0.0
    restart: unless-stopped
EOF
  # Allow docker compose to build the local image rather than trying to pull a non-existent 'dvga:latest'
  touch "$dir/.allow_build"
}

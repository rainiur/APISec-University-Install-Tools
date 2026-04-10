#!/usr/bin/env bash

# Early setup for VAmPI to create .allow_build before build process.
# Expects BASE_DIR, ensure_dir, and log helpers from the main script.
vampi_setup_impl() {
  local dir="$BASE_DIR/vampi"
  ensure_dir "$dir"

  # Create .allow_build file early so installation logic knows to build locally
  touch "$dir/.allow_build"

  # Remove obsolete version attribute from docker-compose.yaml to avoid warnings
  local compose_file="$dir/docker-compose.yml"
  if [[ ! -f "$compose_file" && -f "$dir/docker-compose.yaml" ]]; then
    compose_file="$dir/docker-compose.yaml"
  fi
  if [[ -f "$compose_file" ]]; then
    sed -i '/^version:/d' "$compose_file" || true
  fi

  log INFO "VAmPI configured for local build"
}

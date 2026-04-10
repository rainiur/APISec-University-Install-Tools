#!/usr/bin/env bash

# Post-setup for DVWS.
# Expects BASE_DIR and write_env_port from the main script.
dvws_post_impl() {
  local dir="$BASE_DIR/dvws"
  write_env_port "$dir" DVWS_PORT 8087
  if [[ -f "$dir/docker-compose.yml" ]]; then
    # Remove obsolete version attribute to avoid Docker Compose warnings
    sed -i '/^version:/d' "$dir/docker-compose.yml" || true
    sed -E -i 's/(\s*-\s*")([0-9]{2,5})(:80\")/  - "${DVWS_PORT:-8087}:80"/g' "$dir/docker-compose.yml" || true
  fi
}

#!/usr/bin/env bash

# Post-setup for Pixi.
# Expects BASE_DIR, write_env_port, and log helpers from the main script.
pixi_post_impl() {
  local dir="$BASE_DIR/pixi"

  # Port conflict resolution and docker-compose.yaml fixes are now handled by pixi_setup function.
  # This function focuses on ensuring environment variables are properly set as a backup.
  local env_file="$dir/.env"
  touch "$env_file"

  # Ensure all required port variables are set (backup verification)
  write_env_port "$dir" PIXI_PORT 8084

  # Verify MongoDB port variables are set correctly
  if ! grep -q '^PIXI_MONGO_PORT=' "$env_file"; then
    echo 'PIXI_MONGO_PORT=27018' >> "$env_file"
  fi
  if ! grep -q '^PIXI_MONGO_HTTP_PORT=' "$env_file"; then
    echo 'PIXI_MONGO_HTTP_PORT=28018' >> "$env_file"
  fi

  # Verify app port variables are set correctly
  if ! grep -q '^PIXI_APP_PORT=' "$env_file"; then
    echo 'PIXI_APP_PORT=18000' >> "$env_file"
  fi
  if ! grep -q '^PIXI_ADMIN_PORT=' "$env_file"; then
    echo 'PIXI_ADMIN_PORT=18090' >> "$env_file"
  fi

  log INFO "Pixi post-setup completed - service should be accessible at http://localhost:18000"
}

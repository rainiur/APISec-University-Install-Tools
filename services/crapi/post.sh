#!/usr/bin/env bash

# Post-setup for crAPI.
# Expects BASE_DIR, ensure_dir, and log helpers from the main script.
crapi_post_impl() {
  local dir="$BASE_DIR/crapi"
  ensure_dir "$dir"
  local compose_file="$dir/docker-compose.yml"
  [[ -f "$compose_file" ]] || compose_file="$dir/docker-compose.yaml"
  [[ -f "$compose_file" ]] || return 0

  # Clear Docker build cache to resolve schema file issues
  log INFO "Clearing Docker build cache to resolve crAPI schema file issues"
  docker builder prune -f >/dev/null 2>&1 || true

  # Detect gateway service name in the compose (prefer image name containing "gateway")
  local svc
  svc=$(awk '
    $0 ~ /^services:/ {in_s=1; next}
    # Only treat lines with exactly two leading spaces as service headers
    in_s && $0 ~ /^  [A-Za-z0-9_.-]+:/ {
      svc=$1; sub(":$","",svc)
    }
    in_s && /image:/ && tolower($0) ~ /gateway/ {print svc; exit}
  ' "$compose_file" 2>/dev/null || true)
  if [[ -z "$svc" ]]; then
    # Fallback: find service exposing 443
    svc=$(awk '
      $0 ~ /^services:/ {in_s=1; next}
      # Only treat lines with exactly two leading spaces as service headers
      in_s && $0 ~ /^  [A-Za-z0-9_.-]+:/ {svc=$1; sub(":$","",svc); in_ports=0}
      in_s && /^[[:space:]]+ports:/ {in_ports=1; next}
      in_s && in_ports && /443/ {print svc; exit}
    ' "$compose_file" 2>/dev/null || true)
  fi
  if [[ -z "$svc" ]]; then
    log INFO "crapi_post: could not detect gateway service; removing stale override if present"
    rm -f "$dir/docker-compose.override.yml"
    return 0
  fi
  # Sanity check service name
  case "$svc" in image|services|ports|environment|depends_on|volumes|command|deploy|healthcheck)
    log INFO "crapi_post: detected invalid service name '$svc'; removing stale override"
    rm -f "$dir/docker-compose.override.yml"
    return 0 ;;
  esac

  cat >"$dir/docker-compose.override.yml" <<EOF
services:
  ${svc}:
    healthcheck:
      test: ["CMD-SHELL", "timeout 5 bash -c '</dev/tcp/127.0.0.1/443' || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 60s
EOF

  # Remove obsolete version attribute to avoid Docker Compose warnings
  sed -i '/^version:/d' "$compose_file" || true

  # Force pull images instead of building to avoid schema file issues
  log INFO "Forcing pull of crAPI images to avoid build issues"
  if grep -qE '^\s*build:' "$compose_file"; then
    # Remove build contexts and use pre-built images
    sed -i '/^\s*build:/,/^\s*[^[:space:]]/d' "$compose_file" || true
    # Ensure all services use pre-built images
    sed -i 's/^\(\s*\)build:/\1# build:/' "$compose_file" || true
    # Add image tags for services that might be missing them
    if ! grep -q 'image:' "$compose_file"; then
      log INFO "Adding image references to crAPI services"
      # This is a fallback - the compose file should already have image references
    fi
  fi

  # Create .env file with proper configuration
  local env_file="$dir/.env"
  touch "$env_file"

  # Ensure VERSION is set to latest to use pre-built images
  if ! grep -q '^VERSION=' "$env_file"; then
    echo 'VERSION=latest' >> "$env_file"
  else
    sed -i 's/^VERSION=.*/VERSION=latest/' "$env_file"
  fi

  # Set TLS_ENABLED to false to avoid certificate issues
  if ! grep -q '^TLS_ENABLED=' "$env_file"; then
    echo 'TLS_ENABLED=false' >> "$env_file"
  else
    sed -i 's/^TLS_ENABLED=.*/TLS_ENABLED=false/' "$env_file"
  fi

  # Change HTTPS port from 8443 to 8444 to avoid conflict with Security Shepherd
  if [[ -f "$compose_file" ]]; then
    sed -i 's/8443:443/8444:443/' "$compose_file" || true
    log INFO "Updated crAPI HTTPS port from 8443 to 8444 to avoid Security Shepherd conflict"
  fi

  # Mark as requiring pull instead of build
  ensure_dir "$dir"
  touch "$dir/.force_pull"
  rm -f "$dir/.allow_build"
}

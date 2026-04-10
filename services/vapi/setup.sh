#!/usr/bin/env bash

# Early setup for vAPI to create .allow_build and fix warnings before build process.
# Expects BASE_DIR, ensure_dir, write_env_port, and log helpers from the main script.
vapi_setup_impl() {
  local dir="$BASE_DIR/vapi"
  ensure_dir "$dir"

  # Create .allow_build file early so installation logic knows to build locally
  touch "$dir/.allow_build"

  # Remove obsolete version attribute from docker-compose.yml to avoid warnings
  if [[ -f "$dir/docker-compose.yml" ]]; then
    sed -i '/^version:/d' "$dir/docker-compose.yml" || true
  fi

  # Create/update .env with required variables to silence Docker Compose warnings
  local env_file="$dir/.env"
  if [[ ! -f "$env_file" ]]; then
    log INFO "Creating .env for vAPI with required variables"
    # Generate a Laravel-style base64 key
    local genkey
    genkey="$(openssl rand -base64 32 2>/dev/null || head -c 32 /dev/urandom | base64)"
    # Generate a strong random DB password (URL-safe base64)
    local dbpass
    dbpass="$(openssl rand -base64 24 2>/dev/null | tr -d '\n' | tr '/+' '_-' || head -c 24 /dev/urandom | base64 | tr -d '\n' | tr '/+' '_-')"
    printf '%s\n' \
"APP_NAME=VAPI" \
"APP_ENV=local" \
"APP_KEY=base64:${genkey}" \
"APP_DEBUG=true" \
"APP_URL=http://localhost" \
"PUSHER_APP_KEY=" \
"PUSHER_APP_CLUSTER=" \
"DB_CONNECTION=mysql" \
"DB_HOST=db" \
"DB_PORT=3306" \
"DB_DATABASE=vapi" \
"DB_USERNAME=root" \
"DB_PASSWORD=${dbpass}" \
>> "$env_file"
  else
    # Ensure required keys exist to avoid warnings
    grep -q '^APP_NAME='            "$env_file" || echo 'APP_NAME=VAPI' >>"$env_file"
    grep -q '^PUSHER_APP_KEY='      "$env_file" || echo 'PUSHER_APP_KEY=' >>"$env_file"
    grep -q '^PUSHER_APP_CLUSTER='  "$env_file" || echo 'PUSHER_APP_CLUSTER=' >>"$env_file"
    grep -q '^APP_ENV='             "$env_file" || echo 'APP_ENV=local' >>"$env_file"
    grep -q '^APP_DEBUG='           "$env_file" || echo 'APP_DEBUG=true' >>"$env_file"
    grep -q '^APP_URL='             "$env_file" || echo 'APP_URL=http://localhost' >>"$env_file"
  fi

  # Set port configuration early
  write_env_port "$dir" VAPI_PORT 8000

  log INFO "vAPI configured for local build with environment variables set"
}

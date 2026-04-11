#!/usr/bin/env bash

# Early setup for Pixi to create .allow_build and fix port conflicts before build process.
# Expects BASE_DIR, ensure_dir, write_env_port, and log helpers from the main script.
pixi_setup_impl() {
  local dir="$BASE_DIR/pixi"
  ensure_dir "$dir"

  # Create .allow_build file early so installation logic knows to build locally
  touch "$dir/.allow_build"

  # Support both .yml and .yaml compose filenames and fix port conflicts BEFORE build
  local compose_file="$dir/docker-compose.yml"
  if [[ ! -f "$compose_file" && -f "$dir/docker-compose.yaml" ]]; then
    compose_file="$dir/docker-compose.yaml"
  fi
  if [[ -f "$compose_file" ]]; then
    # Remove obsolete version attribute to avoid Docker Compose warnings
    sed -i '/^version:/d' "$compose_file" || true

    # Fix MongoDB port conflicts (Security Shepherd uses 27017, so use 27018 for Pixi)
    sed -E -i 's/^(\s*)-\s*"27017:27017"/\1- "127.0.0.1:${PIXI_MONGO_PORT:-27018}:27017"/g' "$compose_file" || true
    sed -E -i 's/^(\s*)-\s*"28017:28017"/\1- "127.0.0.1:${PIXI_MONGO_HTTP_PORT:-28018}:28017"/g' "$compose_file" || true

    # Fix app port conflicts (vAPI uses 8000, so use 18000 for Pixi)
    sed -E -i 's/^(\s*)-\s*"8000:8000"/\1- "${PIXI_APP_PORT:-18000}:8000"/g' "$compose_file" || true
    sed -E -i 's/^(\s*)-\s*"8090:8090"/\1- "${PIXI_ADMIN_PORT:-18090}:8090"/g' "$compose_file" || true
  fi

  # Patch the upstream app so malformed or alternate login form fields do not
  # crash the Node process on user.toLowerCase().
  local app_server="$dir/app/server.js"
  if [[ -f "$app_server" ]]; then
    grep -q "user = (user || '').toString().trim().toLowerCase();" "$app_server" || \
      perl -0pi -e "s/user = user\\.toLowerCase\\(\\);/user = \(user || ''\)\.toString\(\)\.trim\(\)\.toLowerCase\(\);\n\t\tif \(!user || !pass\) {\n\t\t\tres.redirect\('\/login'\);\n\t\t\treturn;\n\t\t}/" "$app_server"

    grep -q "req.body.user || req.body.email" "$app_server" || \
      perl -0pi -e "s/app_authenticate\\(req\\.body\\.user, req\\.body\\.pass, req, res\\);/app_authenticate\(req.body.user || req.body.email, req.body.pass || req.body.password, req, res\);/" "$app_server"
  fi

  # Set up port configuration with non-conflicting values
  write_env_port "$dir" PIXI_PORT 8084
  local env_file="$dir/.env"
  touch "$env_file"

  # Set MongoDB ports to avoid conflicts with Security Shepherd (27017 -> 27018, 28017 -> 28018)
  if grep -q '^PIXI_MONGO_PORT=' "$env_file"; then
    sed -i 's/^PIXI_MONGO_PORT=.*/PIXI_MONGO_PORT=27018/' "$env_file"
  else
    echo 'PIXI_MONGO_PORT=27018' >> "$env_file"
  fi
  if grep -q '^PIXI_MONGO_HTTP_PORT=' "$env_file"; then
    sed -i 's/^PIXI_MONGO_HTTP_PORT=.*/PIXI_MONGO_HTTP_PORT=28018/' "$env_file"
  else
    echo 'PIXI_MONGO_HTTP_PORT=28018' >> "$env_file"
  fi

  # Set app ports to avoid conflicts with vAPI (8000 -> 18000, 8090 -> 18090)
  if grep -q '^PIXI_APP_PORT=' "$env_file"; then
    sed -i 's/^PIXI_APP_PORT=.*/PIXI_APP_PORT=18000/' "$env_file"
  else
    echo 'PIXI_APP_PORT=18000' >> "$env_file"
  fi
  if grep -q '^PIXI_ADMIN_PORT=' "$env_file"; then
    sed -i 's/^PIXI_ADMIN_PORT=.*/PIXI_ADMIN_PORT=18090/' "$env_file"
  else
    echo 'PIXI_ADMIN_PORT=18090' >> "$env_file"
  fi

  log INFO "Pixi configured for local build with port conflicts resolved (MongoDB: 27018, App: 18000)"
}

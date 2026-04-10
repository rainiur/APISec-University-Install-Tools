#!/usr/bin/env bash

# Early setup for Security Shepherd to fix image references before build process.
# Expects BASE_DIR, ensure_dir, write_env_port, and log helpers from the main script.
security_shepherd_setup_impl() {
  local dir="$BASE_DIR/security-shepherd"
  ensure_dir "$dir"

  # Replace non-existent OWASP images with official images in docker-compose.yml
  if [[ -f "$dir/docker-compose.yml" ]]; then
    log INFO "Fixing Security Shepherd image references before build"

    # Remove obsolete version attribute from docker-compose.yml
    sed -i '/^version:/d' "$dir/docker-compose.yml" || true

    # Replace non-existent OWASP images with official images
    # Mongo: use stable 4.2 tag for broad compatibility
    sed -E -i 's|(image:\s*)owasp/security-shepherd_mongo|\1mongo:4.2|g' "$dir/docker-compose.yml" || true
    sed -E -i 's|(IMAGE_MONGO:\s*)owasp/security-shepherd_mongo|\1mongo:4.2|g' "$dir/docker-compose.yml" || true
    # MariaDB: map to mariadb:10.6.11 to match DB_VERSION
    sed -E -i 's|(image:\s*)owasp/security-shepherd_mariadb|\1mariadb:10.6.11|g' "$dir/docker-compose.yml" || true
    sed -E -i 's|(IMAGE_MARIADB:\s*)owasp/security-shepherd_mariadb|\1mariadb:10.6.11|g' "$dir/docker-compose.yml" || true
  fi

  # Create/update .env with proper image overrides
  local env_file="$dir/.env"
  touch "$env_file"

  # Set image overrides to public images
  if grep -q '^IMAGE_MONGO=' "$env_file"; then
    sed -i 's/^IMAGE_MONGO=.*/IMAGE_MONGO=mongo:4.2/' "$env_file"
  else
    echo 'IMAGE_MONGO=mongo:4.2' >> "$env_file"
  fi
  if grep -q '^IMAGE_MARIADB=' "$env_file"; then
    sed -i 's/^IMAGE_MARIADB=.*/IMAGE_MARIADB=mariadb:10.6.11/' "$env_file"
  else
    echo 'IMAGE_MARIADB=mariadb:10.6.11' >> "$env_file"
  fi

  # Set ports early and fix conflicts
  write_env_port "$dir" SECURITY_SHEPHERD_PORT 8083
  # Immediately fix port conflicts in .env (force override any existing values)
  if [[ -f "$env_file" ]]; then
    sed -i 's/^DB_PORT_MAPPED_HOST=.*/DB_PORT_MAPPED_HOST=3307/' "$env_file"
    sed -i 's/^TEST_MYSQL_PORT=.*/TEST_MYSQL_PORT=3307/' "$env_file"
    # Also ensure HTTP and HTTPS ports are set to avoid defaults
    sed -i 's/^HTTP_PORT=.*/HTTP_PORT=8083/' "$env_file"
    sed -i 's/^HTTPS_PORT=.*/HTTPS_PORT=8445/' "$env_file"
  fi

  # Security Shepherd requires Maven build to generate target/ files before Docker build
  if [[ -d "$dir" ]]; then
    log INFO "Building Security Shepherd with Maven to generate required files"
    cd "$dir" || return 1

    # Check if Maven is available
    if ! command -v mvn >/dev/null 2>&1; then
      log ERROR "Maven is required but not installed. Please install Maven to build Security Shepherd."
      return 1
    fi

    # Run Maven build to generate target/ directory with required files
    log INFO "Running Maven build to generate target/ directory files"
    if mvn clean compile -q; then
      log INFO "Maven build completed successfully"

      # Copy generated files to locations expected by Dockerfile
      log INFO "Copying generated schema files to expected locations for Docker build"
      if [[ -f "target/classes/database/coreSchema.sql" ]]; then
        cp "target/classes/database/coreSchema.sql" "target/coreSchema.sql"
      fi
      if [[ -f "target/classes/database/moduleSchemas.sql" ]]; then
        cp "target/classes/database/moduleSchemas.sql" "target/moduleSchemas.sql"
      fi
      if [[ -f "target/classes/mongodb/moduleSchemas.js" ]]; then
        cp "target/classes/mongodb/moduleSchemas.js" "target/moduleSchemas.js"
      fi
      # Some upstream revisions place generated files in alternate paths.
      # Try a best-effort search fallback so Docker COPY paths always exist.
      if [[ ! -f "target/coreSchema.sql" ]]; then
        local found_core
        found_core="$(find target -type f -name 'coreSchema.sql' | head -n 1 || true)"
        [[ -n "$found_core" ]] && cp "$found_core" "target/coreSchema.sql"
      fi
      if [[ ! -f "target/moduleSchemas.sql" ]]; then
        local found_module_sql
        found_module_sql="$(find target -type f -name 'moduleSchemas.sql' | head -n 1 || true)"
        [[ -n "$found_module_sql" ]] && cp "$found_module_sql" "target/moduleSchemas.sql"
      fi
      if [[ ! -f "target/moduleSchemas.js" ]]; then
        local found_module_js
        found_module_js="$(find target -type f -name 'moduleSchemas.js' | head -n 1 || true)"
        [[ -n "$found_module_js" ]] && cp "$found_module_js" "target/moduleSchemas.js"
      fi
      if [[ ! -f "target/coreSchema.sql" || ! -f "target/moduleSchemas.sql" || ! -f "target/moduleSchemas.js" ]]; then
        log ERROR "Required Security Shepherd build artifacts missing in target/ (coreSchema.sql, moduleSchemas.sql, moduleSchemas.js)."
        return 1
      fi
      log INFO "Schema files copied to target/ root for Docker build"
    else
      log ERROR "Maven build failed. Security Shepherd requires a successful Maven build before Docker build."
      return 1
    fi
  fi

  # If compose uses local build contexts, allow building
  if [[ -f "$dir/docker-compose.yml" ]] && grep -qE '^\s*build:' "$dir/docker-compose.yml"; then
    touch "$dir/.allow_build"
  fi

  log INFO "Security Shepherd configured with correct image references and Maven build completed"
}

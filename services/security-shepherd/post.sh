#!/usr/bin/env bash

# Post-setup for Security Shepherd.
# Expects BASE_DIR, write_env_port, and log helpers from the main script.
security_shepherd_post_impl() {
  local dir="$BASE_DIR/security-shepherd"

  # Update port mappings in docker-compose.yml (if not already done)
  if [[ -f "$dir/docker-compose.yml" ]]; then
    sed -E -i 's/(\s*-\s*")([0-9]{2,5})(:80\")/  - "${SECURITY_SHEPHERD_PORT:-8083}:80"/g' "$dir/docker-compose.yml" || true
  fi

  # Ensure .env has all required configuration
  local env_file="$dir/.env"
  touch "$env_file"

  # Set HTTP and HTTPS ports to fixed values.
  # Both ports map to Tomcat HTTP (8080) — no HTTPS at container level.
  local http_port="8083"
  local https_port="8445"

  if grep -q '^HTTP_PORT=' "$env_file"; then
    sed -i "s/^HTTP_PORT=.*/HTTP_PORT=${http_port}/" "$env_file"
  else
    echo "HTTP_PORT=${http_port}" >> "$env_file"
  fi

  if grep -q '^HTTPS_PORT=' "$env_file"; then
    sed -i "s/^HTTPS_PORT=.*/HTTPS_PORT=${https_port}/" "$env_file"
  else
    echo "HTTPS_PORT=${https_port}" >> "$env_file"
  fi
  # Generate secure passwords if missing (do not log values)
  if ! grep -q '^DB_PASS=' "$env_file"; then
    local dbpass
    dbpass="$(openssl rand -base64 24 2>/dev/null | tr -d '\n' | tr '/+' '_-' || head -c 24 /dev/urandom | base64 | tr -d '\n' | tr '/+' '_-')"
    echo "DB_PASS=${dbpass}" >> "$env_file"
  fi
  if ! grep -q '^TLS_KEYSTORE_PASS=' "$env_file"; then
    local tlspass
    tlspass="$(openssl rand -base64 24 2>/dev/null | tr -d '\n' | tr '/+' '_-' || head -c 24 /dev/urandom | base64 | tr -d '\n' | tr '/+' '_-')"
    echo "TLS_KEYSTORE_PASS=${tlspass}" >> "$env_file"
  fi

  # Fix port conflicts: move DB host port to 3307 and ensure it's applied
  write_env_port "$dir" SECURITY_SHEPHERD_PORT 8083
  # Force DB port to 3307 to avoid conflicts with other MySQL containers
  sed -i 's/^DB_PORT_MAPPED_HOST=.*/DB_PORT_MAPPED_HOST=3307/' "$env_file" 2>/dev/null || echo 'DB_PORT_MAPPED_HOST=3307' >> "$env_file"
  # Ensure TEST_MYSQL_PORT also uses the remapped port
  sed -i 's/^TEST_MYSQL_PORT=.*/TEST_MYSQL_PORT=3307/' "$env_file" 2>/dev/null || echo 'TEST_MYSQL_PORT=3307' >> "$env_file"

  # Remove stale containers from earlier compose definitions to prevent
  # host port and naming conflicts during subsequent starts.
  docker rm -f secshep_tomcat secshep_mariadb secshep_mongo >/dev/null 2>&1 || true

  # Note: Maven build and .allow_build creation are now handled by security_shepherd_setup function
  log INFO "Security Shepherd post-setup completed"
}

# DB initialisation: run after containers are up to fix the hostname in
# database.properties and import the schema SQL if the core DB is empty.
security_shepherd_db_init_impl() {
  local dir="$BASE_DIR/security-shepherd"
  local mariadb_container="secshep_mariadb"
  local tomcat_container="secshep_tomcat"
  local db_pass
  db_pass="$(grep '^DB_PASS=' "$dir/.env" 2>/dev/null | cut -d= -f2)"
  db_pass="${db_pass:-CowSaysMoo}"

  log INFO "Security Shepherd: waiting for MariaDB to accept connections..."
  local attempts=0
  until docker exec "$mariadb_container" sh -c \
      "mysql -u root -p'${db_pass}' -e 'SELECT 1' >/dev/null 2>&1"; do
    attempts=$(( attempts + 1 ))
    if [[ $attempts -ge 30 ]]; then
      log ERROR "Security Shepherd: MariaDB did not become ready in time"
      return 1
    fi
    sleep 2
  done
  log INFO "Security Shepherd: MariaDB is ready"

  # --- Fix database.properties hostname (pre-built image uses wrong name) ---
  docker exec "$tomcat_container" sh -c \
    "sed -i 's|secshep_mysql|${mariadb_container}|g' /usr/local/tomcat/conf/database.properties" \
    2>/dev/null || true
  log INFO "Security Shepherd: database.properties hostname patched to ${mariadb_container}"

  # --- Import schema SQL files if 'core' DB has no tables yet ---
  local table_count
  table_count="$(docker exec "$mariadb_container" sh -c \
    "mysql -u root -p'${db_pass}' -e \
      'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=\"core\";' \
      2>/dev/null | tail -1" || echo 0)"

  if [[ "${table_count:-0}" -eq 0 ]]; then
    log INFO "Security Shepherd: importing coreSchema.sql..."
    docker exec -i "$mariadb_container" sh -c "mysql -u root -p'${db_pass}' 2>/dev/null" \
      < "$dir/target/coreSchema.sql" || true
    log INFO "Security Shepherd: importing moduleSchemas.sql..."
    docker exec -i "$mariadb_container" sh -c "mysql -u root -p'${db_pass}' 2>/dev/null" \
      < "$dir/target/moduleSchemas.sql" || true
    log INFO "Security Shepherd: schema import done"
  else
    log INFO "Security Shepherd: core DB already has ${table_count} tables — skipping import"
  fi

  # --- Reload Tomcat app context to pick up patched database.properties ---
  docker exec "$tomcat_container" sh -c \
    "touch /usr/local/tomcat/webapps/ROOT/WEB-INF/web.xml" 2>/dev/null || true
  log INFO "Security Shepherd: Tomcat context reload triggered"
}

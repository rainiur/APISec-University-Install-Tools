#!/usr/bin/env bash

# Post-setup for Mutillidae to initialize database.
# Expects BASE_DIR and log helpers from the main script.
mutillidae_post_impl() {
  local dir="$BASE_DIR/mutillidae"
  local port="${MUTILLIDAE_PORT:-8088}"

  log INFO "Waiting for Mutillidae services to be ready..."
  sleep 10

  # Wait for the database to be ready first
  log INFO "Waiting for Mutillidae database to be ready..."
  local db_attempt=1
  local max_db_attempts=30
  while [[ $db_attempt -le $max_db_attempts ]]; do
    if (cd "$dir" && docker compose exec database mariadb -u root -pmutillidae -e "SELECT 1" >/dev/null 2>&1); then
      log INFO "Mutillidae database is ready"
      break
    fi
    log INFO "Waiting for Mutillidae database... (attempt $db_attempt/$max_db_attempts)"
    sleep 5
    ((db_attempt++))
  done

  if [[ $db_attempt -gt $max_db_attempts ]]; then
    log WARN "Mutillidae database did not become ready in time"
    return 1
  fi

  # Wait for the web service to be ready
  local max_attempts=30
  local attempt=1
  while [[ $attempt -le $max_attempts ]]; do
    if curl -s -f "http://localhost:$port/" >/dev/null 2>&1; then
      log INFO "Mutillidae web service is ready"
      break
    fi
    log INFO "Waiting for Mutillidae web service... (attempt $attempt/$max_attempts)"
    sleep 5
    ((attempt++))
  done

  if [[ $attempt -gt $max_attempts ]]; then
    log WARN "Mutillidae web service did not become ready in time"
    return 1
  fi

  # Fix LDAP hostname configuration (directory -> ldap)
  log INFO "Fixing Mutillidae LDAP hostname configuration..."
  if (cd "$dir" && docker compose exec www sed -i "s/'directory'/'ldap'/g" /var/www/mutillidae/includes/ldap-config.inc 2>/dev/null); then
    log INFO "LDAP hostname configuration updated successfully"
  else
    log WARN "Failed to update LDAP hostname configuration - may need manual fix"
  fi

  # Initialize the database
  log INFO "Setting up Mutillidae database..."
  local db_setup_response
  db_setup_response=$(curl -s "http://localhost:$port/set-up-database.php")
  if echo "$db_setup_response" | grep -q "Database reset successful\|Successfully created.*table\|Successfully inserted data"; then
    log INFO "Mutillidae database setup completed successfully"
  else
    log WARN "Mutillidae database setup may have failed - check manually"
    log DEBUG "Database setup response: $db_setup_response"
  fi
}

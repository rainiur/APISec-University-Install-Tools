#!/usr/bin/env bash

# Post-setup for VAmPI.
# Expects BASE_DIR, write_env_port, and log helpers from the main script.
vampi_post_impl() {
  local dir="$BASE_DIR/vampi"
  # Support both .yml and .yaml compose filenames
  local compose_file="$dir/docker-compose.yml"
  if [[ ! -f "$compose_file" && -f "$dir/docker-compose.yaml" ]]; then
    compose_file="$dir/docker-compose.yaml"
  fi
  if [[ -f "$compose_file" ]]; then
    # Remove obsolete version attribute to avoid Docker Compose warnings
    sed -i '/^version:/d' "$compose_file" || true
    write_env_port "$dir" VAMPI_PORT 8086

    # Handle VAmPI port conflicts by using different ports for secure and vulnerable versions
    local backend_port=80
    if grep -q ':5000' "$compose_file"; then
      backend_port=5000
    fi

    awk -v backend_port="$backend_port" '
      /^[[:space:]]*vampi-vulnerable:[[:space:]]*$/ { svc="vuln"; in_ports=0; print; next }
      /^[[:space:]]*vampi-secure:[[:space:]]*$/ { svc="secure"; in_ports=0; print; next }
      /^[[:space:]]*[A-Za-z0-9_.-]+:[[:space:]]*$/ {
        if ($0 !~ /^[[:space:]]*(vampi-vulnerable|vampi-secure):[[:space:]]*$/) {
          svc=""
          in_ports=0
        }
      }
      svc != "" && /^[[:space:]]*ports:[[:space:]]*$/ { in_ports=1; print; next }
      svc != "" && in_ports && /^[[:space:]]*-[[:space:]]*/ {
        if (svc == "vuln") {
          sub(/-[[:space:]]*"?[0-9]{2,5}:[0-9]{2,5}"?/, "- 8086:" backend_port)
        } else if (svc == "secure") {
          sub(/-[[:space:]]*"?[0-9]{2,5}:[0-9]{2,5}"?/, "- 8093:" backend_port)
        }
        in_ports=0
        print
        next
      }
      svc != "" && in_ports && $0 !~ /^[[:space:]]*$/ && $0 !~ /^[[:space:]]*#/ {
        in_ports=0
      }
      { print }
    ' "$compose_file" >"$compose_file.tmp" && mv "$compose_file.tmp" "$compose_file"
  fi

  # Auto-populate VAmPI database after startup
  log INFO "Setting up VAmPI database auto-population"
  # Only add vampi-init if it doesn't already exist in the compose file
  if [[ -f "$compose_file" ]] && ! grep -q "^[[:space:]]*vampi-init:" "$compose_file"; then
    # Add a healthcheck that initializes the database
    cat >>"$compose_file" <<'EOF'

 # VAmPI database initialization service
 vampi-init:
   image: curlimages/curl:latest
   depends_on:
     - vampi-vulnerable
   command: >
     sh -c "
       echo 'Waiting for VAmPI to be ready...' &&
       until curl -f http://vampi-vulnerable:5000/ >/dev/null 2>&1; do sleep 2; done &&
       echo 'VAmPI is ready, initializing database...' &&
       curl -s http://vampi-vulnerable:5000/createdb &&
       echo 'Database initialized successfully'
     "
   restart: "no"
EOF
  elif [[ -f "$compose_file" ]]; then
    log INFO "VAmPI database initialization service already exists in compose file"
  fi
}

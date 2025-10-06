#!/usr/bin/env bash

# Unified manager for vulnerable API/Apps lab services
# Supports: crapi, vapi, dvga, juice-shop
# Location: /opt/lab/<service>
# Usage examples:
#   sudo ./manage_vuln_services.sh install all --expose
#   sudo ./manage_vuln_services.sh update crapi
#   sudo ./manage_vuln_services.sh start vapi
#   sudo ./manage_vuln_services.sh stop all
#   sudo ./manage_vuln_services.sh clean all

set -Eeuo pipefail
trap 'echo "[$(date -u +%FT%TZ)] ERROR at line $LINENO" >&2' ERR

# ---------- logging ----------
log() { printf '%s %-5s %s\n' "$(date -u +%FT%TZ)" "$1" "$2"; } # level, message

# ---------- config ----------
BASE_DIR="/opt/lab"
COMPOSE_CMD="docker compose" # default to plugin
if ! docker compose version >/dev/null 2>&1; then
  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
  else
    log ERROR "Neither 'docker compose' nor 'docker-compose' found. Install Docker Compose first."; exit 1
  fi
fi

# Services map: type defines how to install
# type: compose_url | git | builtin
# extra: optional post-setup (function name)
SERVICES=(
  "name=crapi type=compose_url src=https://raw.githubusercontent.com/OWASP/crAPI/main/deploy/docker/docker-compose.yml expose_prompt=true post=crapi_post"
  "name=vapi type=git src=https://github.com/roottusk/vapi.git expose_prompt=false post=vapi_post"
  "name=dvga type=builtin src=setup_dvga expose_prompt=true"
  "name=juice-shop type=builtin src=setup_juice_shop expose_prompt=false"
  # Additional vulnerable apps
  "name=webgoat type=builtin src=setup_webgoat expose_prompt=false post=webgoat_post"
  "name=dvwa type=builtin src=setup_dvwa expose_prompt=false"
  "name=bwapp type=builtin src=setup_bwapp expose_prompt=false"
  "name=security-shepherd type=git src=https://github.com/OWASP/SecurityShepherd.git expose_prompt=false post=security_shepherd_post"
  "name=pixi type=git src=https://github.com/DevSlop/Pixi.git expose_prompt=true post=pixi_post"
  "name=xvwa type=builtin src=setup_xvwa expose_prompt=false"
  "name=mutillidae type=builtin src=setup_mutillidae expose_prompt=false post=mutillidae_post"
  "name=vampi type=git src=https://github.com/erev0s/VAmPI.git expose_prompt=false post=vampi_post"
  "name=dvws type=builtin src=setup_dvws expose_prompt=false"
  "name=lab-dashboard type=builtin src=setup_lab_dashboard expose_prompt=false"
)

# ---------- helpers ----------
ensure_dir() { local d="$1"; [[ -d "$d" ]] || { log INFO "Creating $d"; mkdir -p "$d"; }; }
write_env_port() { # write or ensure PORT env var in .env
  local dir="$1"; local var="$2"; local val="$3";
  ensure_dir "$dir"
  grep -q "^${var}=" "$dir/.env" 2>/dev/null && sed -i "s/^${var}=.*/${var}=${val}/" "$dir/.env" || echo "${var}=${val}" >>"$dir/.env";
}

# Set Security Shepherd ports to 8083 (HTTP) and 8443 (HTTPS)
security_shepherd_post() {
  local dir="$BASE_DIR/security-shepherd"
  write_env_port "$dir" SECURITY_SHEPHERD_PORT 8083
  
  # Remove obsolete version attribute from docker-compose.yml
  if [[ -f "$dir/docker-compose.yml" ]]; then
    sed -i '/^version:/d' "$dir/docker-compose.yml" || true
    sed -E -i 's/(\s*-\s*")([0-9]{2,5})(:80\")/  - "${SECURITY_SHEPHERD_PORT:-8083}:80"/g' "$dir/docker-compose.yml" || true

    # Replace non-existent OWASP images with official images
    # Mongo: use stable 4.2 tag for broad compatibility
    sed -E -i 's|(image:\s*)owasp/security-shepherd_mongo|\1mongo:4.2|g' "$dir/docker-compose.yml" || true
    sed -E -i 's|(IMAGE_MONGO:\s*)owasp/security-shepherd_mongo|\1mongo:4.2|g' "$dir/docker-compose.yml" || true
    # MariaDB: map to mariadb:10.6.11 to match DB_VERSION
    sed -E -i 's|(image:\s*)owasp/security-shepherd_mariadb|\1mariadb:10.6.11|g' "$dir/docker-compose.yml" || true
    sed -E -i 's|(IMAGE_MARIADB:\s*)owasp/security-shepherd_mariadb|\1mariadb:10.6.11|g' "$dir/docker-compose.yml" || true
  fi

  # Ensure .env has valid images and secure secrets
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
  
  # Set HTTP and HTTPS ports to fixed values
  local http_port="8083"
  local https_port="8443"
  
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

  # Avoid host port conflicts: move DB host port to 3307 (loopback binding remains)
  if grep -q '^DB_PORT_MAPPED_HOST=' "$env_file"; then
    sed -i 's/^DB_PORT_MAPPED_HOST=.*/DB_PORT_MAPPED_HOST=3307/' "$env_file"
  else
    echo 'DB_PORT_MAPPED_HOST=3307' >> "$env_file"
  fi
  
  # Security Shepherd requires Maven build to generate target/ files before Docker build
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
  else
    log ERROR "Maven build failed. Security Shepherd requires a successful Maven build before Docker build."
    return 1
  fi
  
  # If compose uses local build contexts, allow building
  if [[ -f "$dir/docker-compose.yml" ]] && grep -qE '^\s*build:' "$dir/docker-compose.yml"; then
    touch "$dir/.allow_build"
  fi
}

# Fix crAPI gateway healthcheck and handle Docker build issues
crapi_post() {
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
    return 0;;
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

# Fix WebGoat healthcheck (curl missing); use wget
webgoat_post() {
  local dir="$BASE_DIR/webgoat"
  ensure_dir "$dir"
  cat >"$dir/docker-compose.override.yml" <<'EOF'
services:
  webgoat:
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:8080/WebGoat/actuator/health >/dev/null 2>&1 || busybox wget -qO- http://127.0.0.1:8080/WebGoat/actuator/health >/dev/null 2>&1 || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 45s
EOF
}

# Attempt to normalize Pixi port to 8084 if a compose exists
pixi_post() {
  local dir="$BASE_DIR/pixi"
  write_env_port "$dir" PIXI_PORT 8084
  # Support both .yml and .yaml compose filenames
  local compose_file="$dir/docker-compose.yml"
  if [[ ! -f "$compose_file" && -f "$dir/docker-compose.yaml" ]]; then
    compose_file="$dir/docker-compose.yaml"
  fi
  if [[ -f "$compose_file" ]]; then
    # Remove obsolete version attribute to avoid Docker Compose warnings
    sed -i '/^version:/d' "$compose_file" || true
    sed -E -i 's/^(\s*)-\s*"([0-9]{2,5}):80"/\1- "${PIXI_PORT:-8084}:80"/g' "$compose_file" || true
    # Avoid Mongo host port conflicts and restrict to loopback
    sed -E -i 's/^(\s*)-\s*"27017:27017"/\1- "127.0.0.1:${PIXI_MONGO_PORT:-27018}:27017"/g' "$compose_file" || true
    sed -E -i 's/^(\s*)-\s*"28017:28017"/\1- "127.0.0.1:${PIXI_MONGO_HTTP_PORT:-28018}:28017"/g' "$compose_file" || true
    # Remap Pixi app host ports to avoid conflicts and bind to loopback
    sed -E -i 's/^(\s*)-\s*"8000:8000"/\1- "127.0.0.1:${PIXI_APP_PORT:-18000}:8000"/g' "$compose_file" || true
    sed -E -i 's/^(\s*)-\s*"8090:8090"/\1- "127.0.0.1:${PIXI_ADMIN_PORT:-18090}:8090"/g' "$compose_file" || true
  fi
  # Pixi app image is built locally; allow compose to build it
  ensure_dir "$dir"
  touch "$dir/.allow_build"

  # Ensure Pixi .env has Mongo host port variables
  local env_file="$dir/.env"
  touch "$env_file"
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
}

# Normalize VAmPI to host 8086; prefer container 5000 if present, else 80
vampi_post() {
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
    # First, check if both services exist and are trying to use the same port
    if grep -q "vampi-secure:" "$compose_file" && grep -q "vampi-vulnerable:" "$compose_file"; then
      # Use port 8086 for vulnerable (main service) and 8093 for secure
      if grep -qE ':5000"' "$compose_file"; then
        # Update vulnerable service to use port 8086
        sed -E -i '/vampi-vulnerable:/,/environment:/ s/^(\s*)-\s*"([0-9]{2,5}):5000"/\1- "8086:5000"/g' "$compose_file" || true
        # Update secure service to use port 8093
        sed -E -i '/vampi-secure:/,/environment:/ s/^(\s*)-\s*"([0-9]{2,5}):5000"/\1- "8093:5000"/g' "$compose_file" || true
      else
        # Fallback for :80 ports
        sed -E -i '/vampi-vulnerable:/,/environment:/ s/^(\s*)-\s*"([0-9]{2,5}):80"/\1- "8086:80"/g' "$compose_file" || true
        sed -E -i '/vampi-secure:/,/environment:/ s/^(\s*)-\s*"([0-9]{2,5}):80"/\1- "8093:80"/g' "$compose_file" || true
      fi
    else
      # Single service - use standard port mapping
      if grep -qE ':5000"' "$compose_file"; then
        sed -E -i 's/^(\s*)-\s*"([0-9]{2,5}):5000"/\1- "${VAMPI_PORT:-8086}:5000"/g' "$compose_file" || true
      else
        sed -E -i 's/^(\s*)-\s*"([0-9]{2,5}):80"/\1- "${VAMPI_PORT:-8086}:80"/g' "$compose_file" || true
      fi
    fi
  fi
  # Allow building local images for VAmPI
  ensure_dir "$dir"
  touch "$dir/.allow_build"
  
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

# Normalize DVWS to host 8087 (container 80)
dvws_post() {
  local dir="$BASE_DIR/dvws"
  write_env_port "$dir" DVWS_PORT 8087
  if [[ -f "$dir/docker-compose.yml" ]]; then
    # Remove obsolete version attribute to avoid Docker Compose warnings
    sed -i '/^version:/d' "$dir/docker-compose.yml" || true
    sed -E -i 's/(\s*-\s*")([0-9]{2,5})(:80\")/  - "${DVWS_PORT:-8087}:80"/g' "$dir/docker-compose.yml" || true
  fi
}

is_installed() { local svc="$1"; [[ -f "$BASE_DIR/$svc/docker-compose.yml" ]] || [[ -d "$BASE_DIR/$svc/.git" ]]; }

# Safer targeted exposure changer: only change host binding in ports entries
expose_ports_in_compose() {
  local compose_file="$1"
  # Replace only patterns like "- \"127.0.0.1:PORT:...\"" with 0.0.0.0
  sed -E -i '/ports:/,/-/ s/^([[:space:]]*-[[:space:]]*)"127\.0\.0\.1:([0-9]+:)/\10.0.0.0:\2/' "$compose_file"
  # Also handle variable-based binds used by crAPI: "${LISTEN_IP:-127.0.0.1}:PORT:..."
  sed -E -i '/ports:/,/-/ s/^([[:space:]]*-[[:space:]]*")\$\{LISTEN_IP:-127\.0\.0\.1\}:([0-9]+:)/\10.0.0.0:\2/' "$compose_file"
  # And handle unquoted forms if present: - 127.0.0.1:PORT:...
  sed -E -i '/ports:/,/-/ s/^([[:space:]]*-[[:space:]]*)127\.0\.0\.1:([0-9]+:)/\10.0.0.0:\2/' "$compose_file"
}

# ---------- built-in setups ----------
setup_juice_shop() {
  local dir="$BASE_DIR/juice-shop"
  ensure_dir "$dir"
  write_env_port "$dir" JUICESHOP_PORT 3000
  cat >"$dir/docker-compose.yml" <<'EOF'
services:
  juice-shop:
    image: bkimminich/juice-shop
    ports:
      - "${JUICESHOP_PORT:-3000}:3000"
    restart: unless-stopped
EOF
}

setup_dvga() {
  local dir="$BASE_DIR/dvga"
  if [[ ! -f "$dir/Dockerfile" ]]; then
    log INFO "Cloning DVGA (blackhatgraphql branch)"
    git clone -b blackhatgraphql https://github.com/dolevf/Damn-Vulnerable-GraphQL-Application.git "$dir"
    sed -i 's#/opt/dvga#/opt/lab/dvga#g' "$dir/Dockerfile"
  fi
  write_env_port "$dir" DVGA_PORT 5013
  cat >"$dir/docker-compose.yml" <<EOF
services:
  dvga:
    build:
      context: $dir
      dockerfile: Dockerfile
    image: dvga
    container_name: dvga
    ports:
      - "${DVGA_PORT:-5013}:5013"
    environment:
      - WEB_HOST=0.0.0.0
    restart: unless-stopped
EOF
  # Allow docker compose to build the local image rather than trying to pull a non-existent 'dvga:latest'
  touch "$dir/.allow_build"
}

setup_webgoat() {
  local dir="$BASE_DIR/webgoat"
  ensure_dir "$dir"
  write_env_port "$dir" WEBGOAT_PORT 8080
  cat >"$dir/docker-compose.yml" <<'EOF'
services:
  webgoat:
    image: webgoat/webgoat
    ports:
      - "${WEBGOAT_PORT:-8080}:8080"
    restart: unless-stopped
EOF
}

setup_dvwa() {
  local dir="$BASE_DIR/dvwa"
  ensure_dir "$dir"
  write_env_port "$dir" DVWA_PORT 8081
  cat >"$dir/docker-compose.yml" <<'EOF'
services:
  dvwa:
    image: vulnerables/web-dvwa
    ports:
      - "${DVWA_PORT:-8081}:80"
    environment:
      - MYSQL_USER=dvwa
      - MYSQL_PASSWORD=dvwa
      - MYSQL_DATABASE=dvwa
      - MYSQL_ROOT_PASSWORD=dvwa
    command: >
      bash -c "echo 'allow_url_include = On' > /etc/php/7.0/apache2/conf.d/99-custom.ini &&
      echo 'allow_url_fopen = On' >> /etc/php/7.0/apache2/conf.d/99-custom.ini &&
      /main.sh"
    restart: unless-stopped
EOF
}

setup_bwapp() {
  local dir="$BASE_DIR/bwapp"
  ensure_dir "$dir"
  write_env_port "$dir" BWAPP_PORT 8082
  
  # Create Dockerfile that extends hackersploit/bwapp-docker
  cat >"$dir/Dockerfile" <<'EOF'
FROM hackersploit/bwapp-docker

# Create startup script
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Override the default command
CMD ["/start.sh"]
EOF

  # Create startup script
  cat >"$dir/start.sh" <<'EOF'
#!/bin/bash

# Start the original bWAPP services
echo "Starting bWAPP services..."
/run.sh &

# Wait for services to be ready
echo "Waiting for services to be ready..."
sleep 60

# Try to install bWAPP database schema multiple times
echo "Installing bWAPP database schema..."
INSTALL_SUCCESS=false
for i in {1..5}; do
    echo "Attempt $i/5..."
    if curl -s "http://localhost/install.php?install=yes" >/dev/null 2>&1; then
        echo "Database installation successful!"
        INSTALL_SUCCESS=true
        break
    else
        echo "Database installation failed, retrying in 10 seconds..."
        sleep 10
    fi
done

# If automatic installation failed, use manual fallback
if [ "$INSTALL_SUCCESS" = false ]; then
    echo "Automatic installation failed, using manual fallback..."
    
    # Wait for MySQL to be fully ready
    echo "Waiting for MySQL to be ready..."
    sleep 30
    
    # Create database if it doesn't exist
    echo "Creating bWAPP database..."
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS bWAPP;" 2>/dev/null || echo "Database creation may have failed"
    
    # Create tables manually
    echo "Creating database tables..."
    mysql -u root -e "
    USE bWAPP;
    CREATE TABLE IF NOT EXISTS users (id int(10) NOT NULL AUTO_INCREMENT,login varchar(100) DEFAULT NULL,password varchar(100) DEFAULT NULL,email varchar(100) DEFAULT NULL,secret varchar(100) DEFAULT NULL,activation_code varchar(100) DEFAULT NULL,activated tinyint(1) DEFAULT '0',reset_code varchar(100) DEFAULT NULL,admin tinyint(1) DEFAULT '0',PRIMARY KEY (id)) ENGINE=InnoDB  DEFAULT CHARSET=utf8 AUTO_INCREMENT=1;
    INSERT IGNORE INTO users (login, password, email, secret, activation_code, activated, reset_code, admin) VALUES ('A.I.M.', '6885858486f31043e5839c735d99457f045affd0', 'bwapp-aim@mailinator.com', 'A.I.M. or Authentication Is Missing', NULL, 1, NULL, 1),('bee', '6885858486f31043e5839c735d99457f045affd0', 'bwapp-bee@mailinator.com', 'Any bugs?', NULL, 1, NULL, 1);
    CREATE TABLE IF NOT EXISTS blog (id int(10) NOT NULL AUTO_INCREMENT,owner varchar(100) DEFAULT NULL,entry varchar(500) DEFAULT NULL,date datetime DEFAULT NULL,PRIMARY KEY (id)) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1;
    CREATE TABLE IF NOT EXISTS visitors (id int(10) NOT NULL AUTO_INCREMENT,ip_address varchar(50) DEFAULT NULL,user_agent varchar(500) DEFAULT NULL,date datetime DEFAULT NULL,PRIMARY KEY (id)) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1;
    CREATE TABLE IF NOT EXISTS movies (id int(10) NOT NULL AUTO_INCREMENT,title varchar(100) DEFAULT NULL,release_year varchar(100) DEFAULT NULL,genre varchar(100) DEFAULT NULL,main_character varchar(100) DEFAULT NULL,imdb varchar(100) DEFAULT NULL,tickets_stock int(10) DEFAULT NULL,PRIMARY KEY (id)) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1;
    INSERT IGNORE INTO movies (title, release_year, genre, main_character, imdb, tickets_stock) VALUES ('G.I. Joe: Retaliation', '2013', 'action', 'Cobra Commander', 'tt1583421', 100),('Iron Man', '2008', 'action', 'Tony Stark', 'tt0371746', 53),('Man of Steel', '2013', 'action', 'Clark Kent', 'tt0770828', 78),('Terminator Salvation', '2009', 'sci-fi', 'John Connor', 'tt0438488', 100),('The Amazing Spider-Man', '2012', 'action', 'Peter Parker', 'tt0948470', 13),('The Cabin in the Woods', '2011', 'horror', 'Some zombies', 'tt1259521', 666),('The Dark Knight Rises', '2012', 'action', 'Bruce Wayne', 'tt1345836', 3);
    CREATE TABLE IF NOT EXISTS heroes (id int(10) NOT NULL AUTO_INCREMENT,login varchar(100) DEFAULT NULL,password varchar(100) DEFAULT NULL,secret varchar(100) DEFAULT NULL,PRIMARY KEY (id)) ENGINE=InnoDB  DEFAULT CHARSET=utf8 AUTO_INCREMENT=1;
    INSERT IGNORE INTO heroes (login, password, secret) VALUES ('neo', 'trinity', 'Oh why didn\'t I took that BLACK pill?'),('alice', 'loveZombies', 'There\'s a cure!'),('thor', 'Asgard', 'Oh, no... this is Earth... isn\'t it?'),('wolverine', 'Log@N', 'What\'s a Magneto?'),('johnny', 'm3ph1st0ph3l3s', 'I\'m the Ghost Rider!'),('seline', 'm00n', 'It wasn\'t the Lycans. It was you.');
    " 2>/dev/null || echo "Manual database creation may have failed"
    
    echo "Manual database installation completed!"
fi

# Wait a moment for database installation to complete
sleep 10

echo "bWAPP is ready! Access at http://localhost"
echo "Default credentials: bee / bug"

# Keep the original services running
wait
EOF

  # Create docker-compose.yml
  cat >"$dir/docker-compose.yml" <<'EOF'
services:
  bwapp:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "${BWAPP_PORT:-8082}:80"
    restart: unless-stopped
    volumes:
      - bwapp_data:/var/lib/mysql

volumes:
  bwapp_data:
EOF

  # Allow docker compose to build the local image
  ensure_dir "$dir"
  touch "$dir/.allow_build"
}

setup_xvwa() {
  local dir="$BASE_DIR/xvwa"
  ensure_dir "$dir"
  write_env_port "$dir" XVWA_PORT 8085
  # Ensure a valid image is set via .env (default to bitnetsecdave/xvwa - v2 manifest)
  if grep -q '^IMAGE_XVWA=' "$dir/.env" 2>/dev/null; then
    sed -i 's/^IMAGE_XVWA=.*/IMAGE_XVWA=bitnetsecdave\/xvwa/' "$dir/.env"
  else
    echo 'IMAGE_XVWA=bitnetsecdave/xvwa' >> "$dir/.env"
  fi
  cat >"$dir/docker-compose.yml" <<'EOF'
services:
  xvwa:
    image: ${IMAGE_XVWA}
    ports:
      - "${XVWA_PORT:-8085}:80"
    restart: unless-stopped
EOF
}

setup_mutillidae() {
  local dir="$BASE_DIR/mutillidae"
  ensure_dir "$dir"
  write_env_port "$dir" MUTILLIDAE_PORT 8088
  
  # Clone the official mutillidae-docker repository
  if [[ ! -d "$dir/mutillidae-docker" ]]; then
    log INFO "Cloning official mutillidae-docker repository"
    git clone https://github.com/webpwnized/mutillidae-docker.git "$dir/mutillidae-docker"
  fi
  
  # Create a custom docker-compose.yml that uses the official setup but with custom ports
  cat >"$dir/docker-compose.yml" <<EOF
services:
  # Database Service
  database:
    container_name: mutillidae-database
    image: webpwnized/mutillidae:database
    networks:
      - datanet
    restart: unless-stopped

  # Web Application (Mutillidae)
  www:
    container_name: mutillidae-www
    depends_on:
      - database
    image: webpwnized/mutillidae:www
    ports:
      - "\${MUTILLIDAE_PORT:-8088}:80"
      - "\${MUTILLIDAE_HTTPS_PORT:-8445}:443"
    networks:
      - datanet
    restart: unless-stopped

  # Database Admin Interface (phpMyAdmin)
  database_admin:
    container_name: mutillidae-database-admin
    depends_on:
      - database
    image: webpwnized/mutillidae:database_admin
    ports:
      - "127.0.0.1:\${MUTILLIDAE_ADMIN_PORT:-8089}:80"
    networks:
      - datanet
    restart: unless-stopped

  # LDAP Directory Service
  ldap:
    container_name: mutillidae-ldap
    image: webpwnized/mutillidae:ldap
    ports:
      - "127.0.0.1:389:389"
    volumes:
      - ldap_data:/var/lib/ldap
      - ldap_config:/etc/ldap/slapd.d
    networks:
      - ldapnet
    restart: unless-stopped

  # LDAP Admin Interface
  ldap_admin:
    container_name: mutillidae-ldap-admin
    depends_on:
      - ldap
    image: webpwnized/mutillidae:ldap_admin
    ports:
      - "127.0.0.1:\${MUTILLIDAE_LDAP_ADMIN_PORT:-8090}:80"
    networks:
      - ldapnet
    restart: unless-stopped

volumes:
  ldap_data:
  ldap_config:

networks:
  datanet:
    driver: bridge
  ldapnet:
    driver: bridge
EOF

  # Set additional environment variables
  write_env_port "$dir" MUTILLIDAE_HTTPS_PORT 8445
  write_env_port "$dir" MUTILLIDAE_ADMIN_PORT 8089
  write_env_port "$dir" MUTILLIDAE_LDAP_ADMIN_PORT 8090
}

# Post-setup function for Mutillidae to initialize database
mutillidae_post() {
  local dir="$BASE_DIR/mutillidae"
  local port="${MUTILLIDAE_PORT:-8088}"
  
  log INFO "Waiting for Mutillidae services to be ready..."
  sleep 10
  
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

setup_dvws() {
  local dir="$BASE_DIR/dvws"
  ensure_dir "$dir"
  write_env_port "$dir" DVWS_PORT 8087
  cat >"$dir/docker-compose.yml" <<'EOF'
services:
  dvws:
    image: cyrivs89/web-dvws
    ports:
      - "127.0.0.1:${DVWS_PORT:-8087}:80"
    restart: unless-stopped
EOF
}

setup_lab_dashboard() {
  local dir="$BASE_DIR/lab-dashboard"
  ensure_dir "$dir"
  write_env_port "$dir" DASHBOARD_PORT 80
  
  # Get the server's IP address
  local server_ip
  server_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
  
  # Create HTML dashboard
  cat >"$dir/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Security Testing Lab Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        
        .header {
            text-align: center;
            color: white;
            margin-bottom: 40px;
        }
        
        .header h1 {
            font-size: 3rem;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        
        .header p {
            font-size: 1.2rem;
            opacity: 0.9;
        }
        
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        
        .card {
            background: white;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
            border-left: 5px solid #667eea;
        }
        
        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 15px 40px rgba(0,0,0,0.3);
        }
        
        .card h3 {
            color: #333;
            margin-bottom: 10px;
            font-size: 1.4rem;
        }
        
        .card p {
            color: #666;
            margin-bottom: 15px;
            line-height: 1.6;
        }
        
        .card .port {
            background: #f8f9fa;
            padding: 5px 10px;
            border-radius: 20px;
            font-size: 0.9rem;
            color: #495057;
            display: inline-block;
            margin-bottom: 15px;
        }
        
        .card .access-btn {
            display: inline-block;
            background: linear-gradient(45deg, #667eea, #764ba2);
            color: white;
            padding: 12px 25px;
            text-decoration: none;
            border-radius: 25px;
            font-weight: bold;
            transition: all 0.3s ease;
            box-shadow: 0 4px 15px rgba(102, 126, 234, 0.4);
        }
        
        .card .access-btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(102, 126, 234, 0.6);
        }
        
        .card .external-link {
            color: #0366d6;
            text-decoration: underline;
            margin-top: 10px;
            display: inline-block;
        }
        
        .card .external-link:hover {
            text-decoration: none;
        }
        
        .status {
            text-align: center;
            margin-top: 30px;
            color: white;
            font-size: 1.1rem;
        }
        
        .footer {
            text-align: center;
            color: white;
            margin-top: 40px;
            opacity: 0.8;
        }
        
        .category {
            margin-bottom: 30px;
        }
        
        .category h2 {
            color: white;
            margin-bottom: 20px;
            font-size: 1.8rem;
            text-shadow: 1px 1px 2px rgba(0,0,0,0.3);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔒 Security Testing Lab Dashboard</h1>
            <p>Vulnerable Applications for Comprehensive Security Testing & Learning</p>
        </div>
        
        <div class="category">
            <h2>🚀 API Security Testing</h2>
            <div class="grid">
                <div class="card">
                    <h3>crAPI</h3>
                    <div class="port">Port: 8888/8444</div>
                    <p>Completely Ridiculous API - A vulnerable API designed for learning API security concepts including authentication, authorization, and data validation vulnerabilities.</p>
                    <a href="http://${server_ip}:8888" target="_blank" class="access-btn">Access crAPI</a>
                    <br><a href="https://github.com/OWASP/crAPI" target="_blank" class="external-link">GitHub</a>
                </div>
                
                 <div class="card">
                     <h3>VAmPI</h3>
                     <div class="port">Port: 8086</div>
                     <p>Vulnerable API - A deliberately vulnerable API built with Flask to demonstrate common API security issues and attack vectors.</p>
                     <a href="http://${server_ip}:8086/ui/" target="_blank" class="access-btn">Access VAmPI Swagger UI</a>
                     <br><a href="https://github.com/erev0s/VAmPI" target="_blank" class="external-link">GitHub</a>
                 </div>
                
                <div class="card">
                    <h3>VAPI</h3>
                    <div class="port">Port: 8000</div>
                    <p>Vulnerable API - A Laravel-based vulnerable API designed for testing various security vulnerabilities in web APIs.</p>
                    <a href="http://${server_ip}:8000/vapi/" target="_blank" class="access-btn">Access VAPI</a>
                    <br><a href="https://github.com/roottusk/vapi" target="_blank" class="external-link">GitHub</a>
                </div>
                
                <div class="card">
                    <h3>DVGA</h3>
                    <div class="port">Port: 5013</div>
                    <p>Damn Vulnerable GraphQL Application - A vulnerable GraphQL API designed for learning GraphQL security testing.</p>
                    <a href="http://${server_ip}:5013" target="_blank" class="access-btn">Access DVGA</a>
                    <br><a href="https://github.com/dolevf/Damn-Vulnerable-GraphQL-Application" target="_blank" class="external-link">GitHub</a>
                </div>
            </div>
        </div>
        
        <div class="category">
            <h2>🌐 Web Application Security</h2>
            <div class="grid">
                <div class="card">
                    <h3>DVWA</h3>
                    <div class="port">Port: 8081</div>
                    <p>Damn Vulnerable Web Application - A PHP/MySQL web application that is deliberately vulnerable for learning web application security.</p>
                    <a href="http://${server_ip}:8081" target="_blank" class="access-btn">Access DVWA</a>
                    <br><a href="https://github.com/digininja/DVWA" target="_blank" class="external-link">GitHub</a>
                </div>
                
                <div class="card">
                    <h3>bWAPP</h3>
                    <div class="port">Port: 8082</div>
                    <p>Buggy Web Application - A PHP application with over 100 web vulnerabilities for learning and practicing web security.</p>
                    <a href="http://${server_ip}:8082" target="_blank" class="access-btn">Access bWAPP</a>
                    <br><a href="http://www.itsecgames.com/" target="_blank" class="external-link">Website</a>
                </div>
                
                <div class="card">
                    <h3>XVWA</h3>
                    <div class="port">Port: 8085</div>
                    <p>Xtreme Vulnerable Web Application - A vulnerable web application designed for learning web application security testing.</p>
                    <a href="http://${server_ip}:8085/xvwa" target="_blank" class="access-btn">Access XVWA</a>
                    <br><a href="https://hub.docker.com/r/bitnetsecdave/xvwa" target="_blank" class="external-link">Docker Hub</a>
                </div>
                
                <div class="card">
                    <h3>Mutillidae</h3>
                    <div class="port">Port: 8088</div>
                    <p>OWASP Mutillidae - A deliberately vulnerable web application with numerous vulnerabilities for learning web security.</p>
                    <a href="http://${server_ip}:8088" target="_blank" class="access-btn">Access Mutillidae</a>
                    <br><a href="https://github.com/OWASP/Mutillidae-II" target="_blank" class="external-link">GitHub</a>
                </div>
                
                <div class="card">
                    <h3>DVWS</h3>
                    <div class="port">Port: 8087</div>
                    <p>Damn Vulnerable Web Services - A vulnerable web services application for learning web service security testing.</p>
                    <a href="http://${server_ip}:8087" target="_blank" class="access-btn">Access DVWS</a>
                    <br><a href="https://github.com/snoopysecurity/dvws" target="_blank" class="external-link">GitHub</a>
                </div>
            </div>
        </div>
        
        <div class="category">
            <h2>🎯 Specialized Security Testing</h2>
            <div class="grid">
                <div class="card">
                    <h3>Security Shepherd</h3>
                    <div class="port">Port: 8083/8443</div>
                    <p>OWASP Security Shepherd - A web and mobile application security training platform with various security challenges.</p>
                    <a href="https://${server_ip}:8443" target="_blank" class="access-btn">Access Security Shepherd (HTTPS)</a>
                    <br><a href="https://github.com/OWASP/SecurityShepherd" target="_blank" class="external-link">GitHub</a>
                </div>
                
                <div class="card">
                    <h3>WebGoat</h3>
                    <div class="port">Port: 8080</div>
                    <p>OWASP WebGoat - A deliberately insecure web application maintained by OWASP for learning web application security.</p>
                    <a href="http://${server_ip}:8080" target="_blank" class="access-btn">Access WebGoat</a>
                    <br><a href="https://github.com/WebGoat/WebGoat" target="_blank" class="external-link">GitHub</a>
                </div>
                
                <div class="card">
                    <h3>Juice Shop</h3>
                    <div class="port">Port: 3000</div>
                    <p>OWASP Juice Shop - A modern vulnerable web application written in Node.js and Angular for learning web security.</p>
                    <a href="http://${server_ip}:3000" target="_blank" class="access-btn">Access Juice Shop</a>
                    <br><a href="https://github.com/juice-shop/juice-shop" target="_blank" class="external-link">GitHub</a>
                </div>
                
                <div class="card">
                    <h3>Pixi</h3>
                    <div class="port">Port: 18000</div>
                    <p>Pixi - A vulnerable application for learning various security concepts and attack techniques.</p>
                    <a href="http://${server_ip}:18000" target="_blank" class="access-btn">Access Pixi</a>
                    <br><a href="https://github.com/DevSlop/Pixi" target="_blank" class="external-link">GitHub</a>
                </div>
            </div>
        </div>
        
        <div class="status">
            <p>🟢 All services are running and ready for security testing!</p>
        </div>
        
        <div class="footer">
            <p>🔒 Security Testing University Lab Environment</p>
            <p>Use these applications responsibly for educational purposes only</p>
        </div>
    </div>
</body>
</html>
EOF

   cat >"$dir/docker-compose.yml" <<'EOF'
services:
  dashboard:
    image: nginx:alpine
    ports:
      - "${DASHBOARD_PORT:-80}:80"
    volumes:
      - ./index.html:/usr/share/nginx/html/index.html:ro
    restart: unless-stopped
EOF
}

vapi_post() {
  local dir="$BASE_DIR/vapi"
  # Parameterize host port via env for maintainability
  write_env_port "$dir" VAPI_PORT 8000
  if [[ -f "$dir/docker-compose.yml" ]]; then
    # Remove obsolete version attribute to avoid Docker Compose warnings
    sed -i '/^version:/d' "$dir/docker-compose.yml" || true
    # Replace host port before :80 with ${VAPI_PORT:-8000}, preserving original indentation
    sed -E -i 's/^(\s*)-\s*"([0-9]{2,5}):80"/\1- "${VAPI_PORT:-8000}:80"/g' "$dir/docker-compose.yml" || true

    # Normalize indentation of list items under any 'ports:' key to avoid YAML parse errors
    awk '
      function indent(s){n=match(s,/[^ ]/); return n?substr(s,1,n-1):s}
      BEGIN{ports_indent=""; in_ports=0}
      {
        if ($0 ~ /^[[:space:]]*ports:[[:space:]]*$/) { ports_indent=indent($0); in_ports=1; print $0; next }
        if (in_ports) {
          if ($0 ~ /^[[:space:]]*-/ || $0 ~ /^[[:space:]]*#/) { printf "%s  %s\n", ports_indent, gensub(/^[[:space:]]*/, "", 1, $0); next }
          if ($0 ~ /^[[:space:]]*$/) { print $0; next }
          in_ports=0
        }
        print $0
      }
    ' "$dir/docker-compose.yml" > "$dir/docker-compose.yml.__tmp" && mv "$dir/docker-compose.yml.__tmp" "$dir/docker-compose.yml" || true
  fi

  # Create or populate .env with required variables per vAPI README to silence compose warnings
  local env_file="$dir/.env"
  if [[ ! -f "$env_file" ]]; then
    log INFO "Creating .env for vapi"
    # Generate a Laravel-style base64 key if possible; do not echo the value to logs
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
    # Ensure required keys exist; append only if missing (do not overwrite existing values)
    grep -q '^APP_NAME='            "$env_file" || echo 'APP_NAME=VAPI' >>"$env_file"
    grep -q '^PUSHER_APP_KEY='      "$env_file" || echo 'PUSHER_APP_KEY=' >>"$env_file"
    grep -q '^PUSHER_APP_CLUSTER='  "$env_file" || echo 'PUSHER_APP_CLUSTER=' >>"$env_file"
    grep -q '^APP_ENV='             "$env_file" || echo 'APP_ENV=local' >>"$env_file"
    grep -q '^APP_DEBUG='           "$env_file" || echo 'APP_DEBUG=true' >>"$env_file"
    grep -q '^APP_URL='             "$env_file" || echo 'APP_URL=http://localhost' >>"$env_file"
    grep -q '^DB_CONNECTION='       "$env_file" || echo 'DB_CONNECTION=mysql' >>"$env_file"
    grep -q '^DB_HOST='             "$env_file" || echo 'DB_HOST=db' >>"$env_file"
    grep -q '^DB_PORT='             "$env_file" || echo 'DB_PORT=3306' >>"$env_file"
    grep -q '^DB_DATABASE='         "$env_file" || echo 'DB_DATABASE=vapi' >>"$env_file"
    grep -q '^DB_USERNAME='          "$env_file" || echo 'DB_USERNAME=root' >>"$env_file"
    if ! grep -q '^DB_PASSWORD=' "$env_file"; then
      local dbpass
      dbpass="$(openssl rand -base64 24 2>/dev/null | tr -d '\n' | tr '/+' '_-' || head -c 24 /dev/urandom | base64 | tr -d '\n' | tr '/+' '_-')"
      echo "DB_PASSWORD=${dbpass}" >>"$env_file"
    fi
    if ! grep -q '^APP_KEY=' "$env_file"; then
      local genkey
      genkey="$(openssl rand -base64 32 2>/dev/null || head -c 32 /dev/urandom | base64)"
      echo "APP_KEY=base64:${genkey}" >>"$env_file"
    fi
  fi

  # Enhanced vAPI setup: Database schema import and Laravel initialization
  log INFO "Setting up vAPI database schema and Laravel initialization"
  
  # Check if vapi.sql exists in the repository
  local sql_file="$dir/vapi.sql"
  if [[ -f "$sql_file" ]]; then
    log INFO "Found vapi.sql, will import during container startup"
  else
    log INFO "vapi.sql not found in repository, checking for alternative database files"
    # Look for other SQL files that might contain the schema
    local alt_sql_files=("$dir/database.sql" "$dir/database/database.sql" "$dir/database.sqlite" "$dir/database/database.sqlite")
    for alt_file in "${alt_sql_files[@]}"; do
      if [[ -f "$alt_file" ]]; then
        log INFO "Found alternative database file: $(basename "$alt_file")"
        break
      fi
    done
  fi

  # Create enhanced docker-compose.yml with proper service structure
  if [[ -f "$dir/docker-compose.yml" ]]; then
    log INFO "Creating enhanced vAPI docker-compose.yml with initialization services"
    # Backup original compose file
    cp "$dir/docker-compose.yml" "$dir/docker-compose.yml.backup"
    
    # Create a new compose file with proper structure
    cat > "$dir/docker-compose.yml" << 'EOF'
services:
  www:
    build: .
    ports: 
      - "${VAPI_PORT:-8000}:80"
    volumes:
        - ./vapi:/var/www/html/vapi
    links:
        - db
    networks:
        - default
    environment:
      APP_NAME: Laravel
      APP_ENV: local
      APP_KEY: "base64:JUXTsCKQubRlvxGv6sVwkFL2rJ/gSksD4B/68948Mww:"
      APP_DEBUG: "true"
      APP_URL: http://vapi.test
      SERVER_PORT: 80
      LOG_CHANNEL: errorlog
      LOG_LEVEL: debug
      DB_CONNECTION: mysql
      DB_HOST: db
      DB_PORT: 3306
      DB_DATABASE: vapi
      DB_USERNAME: root
      DB_PASSWORD: vapi123456
      BROADCAST_DRIVER: log
      CACHE_DRIVER: file
      FILESYSTEM_DRIVER: local
      QUEUE_CONNECTION: sync
      SESSION_DRIVER: file
      SESSION_LIFETIME: 120
      MEMCACHED_HOST: 127.0.0.1
      REDIS_HOST: 127.0.0.1
      REDIS_PASSWORD: ""
      REDIS_PORT: 6379
      MAIL_MAILER: smtp
      MAIL_HOST: mailhog
      MAIL_PORT: 1025
      MAIL_USERNAME: ""
      MAIL_PASSWORD: ""
      MAIL_ENCRYPTION: ""
      MAIL_FROM_ADDRESS: ""
      MAIL_FROM_NAME: "${APP_NAME}"
      AWS_ACCESS_KEY_ID:
      AWS_SECRET_ACCESS_KEY:
      AWS_DEFAULT_REGION: us-east-1
      AWS_BUCKET:
      AWS_USE_PATH_STYLE_ENDPOINT: "false"
      PUSHER_APP_ID:
      PUSHER_APP_KEY:
      PUSHER_APP_SECRET:
      PUSHER_APP_CLUSTER: mt1
      MIX_PUSHER_APP_KEY: "${PUSHER_APP_KEY}"
      MIX_PUSHER_APP_CLUSTER: "${PUSHER_APP_CLUSTER}"
    depends_on:
      - db
      - vapi-init
      - vapi-laravel-init

  db:
    image: mysql:8.0
    ports: 
      - "3306:3306"
    command: --default-authentication-plugin=mysql_native_password
    environment:
        MYSQL_DATABASE: vapi
        MYSQL_USER: vapi
        MYSQL_PASSWORD: vapi123456
        MYSQL_ROOT_PASSWORD: vapi123456
    volumes:
        - ./database:/docker-entrypoint-initdb.d
        - ./conf:/etc/mysql/conf.d
        - persistent:/var/lib/mysql
    networks:
        - default

  phpmyadmin:
    image: phpmyadmin/phpmyadmin
    links: 
        - db:db
    ports:
      - 8001:80
    environment:
        MYSQL_USER: user
        MYSQL_PASSWORD: test
        MYSQL_ROOT_PASSWORD: test
    networks:
        - default

  # vAPI database initialization service
  vapi-init:
    image: mysql:8.0
    depends_on:
      - db
    environment:
      - MYSQL_ROOT_PASSWORD=${DB_PASSWORD}
      - MYSQL_DATABASE=${DB_DATABASE}
    command: >
      sh -c "
        echo 'Waiting for MySQL to be ready...' &&
        until mysql -h db -u root -p${DB_PASSWORD} -e 'SELECT 1' >/dev/null 2>&1; do sleep 2; done &&
        echo 'MySQL is ready, checking for database schema...' &&
        if [ -f /vapi/vapi.sql ]; then
          echo 'Importing vapi.sql schema...' &&
          mysql -h db -u root -p${DB_PASSWORD} ${DB_DATABASE} < /vapi/vapi.sql &&
          echo 'Database schema imported successfully'
        else
          echo 'vapi.sql not found, creating basic database structure...' &&
          mysql -h db -u root -p${DB_PASSWORD} ${DB_DATABASE} -e 'CREATE TABLE IF NOT EXISTS users (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(255), email VARCHAR(255), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);' &&
          echo 'Basic database structure created'
        fi
      "
    volumes:
      - .:/vapi
    restart: "no"
    networks:
        - default

  # vAPI Laravel initialization service
  vapi-laravel-init:
    build:
      context: .
      dockerfile: Dockerfile
    depends_on:
      - db
      - vapi-init
    environment:
      - DB_HOST=db
      - DB_DATABASE=${DB_DATABASE}
      - DB_USERNAME=root
      - DB_PASSWORD=${DB_PASSWORD}
    command: >
      sh -c "
        echo 'Waiting for database initialization to complete...' &&
        sleep 10 &&
        echo 'Running Laravel migrations and seeding...' &&
        php artisan migrate --force &&
        php artisan db:seed --force &&
        php artisan key:generate --force &&
        echo 'Laravel initialization completed successfully'
      "
    volumes:
      - .:/var/www/html
    restart: "no"
    networks:
        - default

networks:
  default:

volumes:
  persistent:
EOF
  fi

  # Create Postman collections directory and download collections
  local postman_dir="$dir/postman"
  ensure_dir "$postman_dir"
  
  # Download Postman collections if they don't exist
  if [[ ! -f "$postman_dir/vAPI.postman_collection.json" ]]; then
    log INFO "Downloading vAPI Postman collection"
    # Try to download from the repository or create a basic collection
    if curl -fsSL -o "$postman_dir/vAPI.postman_collection.json" "https://raw.githubusercontent.com/roottusk/vapi/main/vAPI.postman_collection.json" 2>/dev/null; then
      log INFO "Downloaded vAPI Postman collection"
    else
      log INFO "Creating basic vAPI Postman collection"
      cat >"$postman_dir/vAPI.postman_collection.json" <<'EOF'
{
  "info": {
    "name": "vAPI Collection",
    "description": "Vulnerable API Collection for OWASP API Top 10 scenarios",
    "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
  },
  "item": [
    {
      "name": "Authentication",
      "item": [
        {
          "name": "Login",
          "request": {
            "method": "POST",
            "header": [],
            "body": {
              "mode": "raw",
              "raw": "{\n  \"email\": \"{{email}}\",\n  \"password\": \"{{password}}\"\n}"
            },
            "url": {
              "raw": "{{base_url}}/api/login",
              "host": ["{{base_url}}"],
              "path": ["api", "login"]
            }
          }
        }
      ]
    }
  ],
  "variable": [
    {
      "key": "base_url",
      "value": "http://localhost:8000"
    },
    {
      "key": "email",
      "value": "admin@vapi.com"
    },
    {
      "key": "password",
      "value": "password"
    }
  ]
}
EOF
    fi
  fi

  if [[ ! -f "$postman_dir/vAPI_ENV.postman_environment.json" ]]; then
    log INFO "Creating vAPI Postman environment"
    cat >"$postman_dir/vAPI_ENV.postman_environment.json" <<'EOF'
{
  "id": "vapi-environment",
  "name": "vAPI Environment",
  "values": [
    {
      "key": "base_url",
      "value": "http://localhost:8000",
      "enabled": true
    },
    {
      "key": "email",
      "value": "admin@vapi.com",
      "enabled": true
    },
    {
      "key": "password",
      "value": "password",
      "enabled": true
    },
    {
      "key": "token",
      "value": "",
      "enabled": true
    }
  ],
  "_postman_variable_scope": "environment"
}
EOF
  fi

  # Create setup instructions file
  cat >"$dir/SETUP_INSTRUCTIONS.md" <<'EOF'
# vAPI Setup Instructions

## Database Setup
The database schema will be automatically imported during container startup.

## Laravel Setup
Laravel will be automatically initialized with migrations and seeding.

## Postman Setup
1. Import the Postman collection: `postman/vAPI.postman_collection.json`
2. Import the environment: `postman/vAPI_ENV.postman_environment.json`
3. Or use the public workspace: https://www.postman.com/roottusk/workspace/vapi/

## Usage
- Access the API at: http://localhost:8000
- Documentation available at: http://localhost:8000/docs
- Use the Postman collection to test various API security scenarios

## Requirements Met
✅ Docker Compose setup with `docker-compose up -d`
✅ Database schema import (vapi.sql)
✅ Laravel server initialization
✅ Postman collection and environment files
✅ MySQL database configuration
✅ Environment variables setup
EOF

  # If compose uses local build contexts, allow building
  if [[ -f "$dir/docker-compose.yml" ]] && grep -qE '^\s*build:' "$dir/docker-compose.yml"; then
    ensure_dir "$dir"
    touch "$dir/.allow_build"
  fi
}

# ---------- core actions ----------
install_or_update_service() {
  local name="$1"; local type="$2"; local src="$3"; local expose_prompt="$4"; local post="${5:-}"
  local dir="$BASE_DIR/$name"
  ensure_dir "$dir"

  case "$type" in
    compose_url)
      local compose="$dir/docker-compose.yml"; local sumfile="$dir/.compose.sha256"
      if [[ ! -f "$compose" ]]; then
        log INFO "Downloading compose for $name"
        curl -fsSL -o "$compose" "$src"
        sha256sum "$compose" | awk '{print $1}' >"$sumfile"
      else
        log INFO "Updating compose for $name (TOFU checksum)"
        local oldsum="$(cat "$sumfile" 2>/dev/null || true)"
        curl -fsSL -o "$compose.new" "$src"
        local newsum="$(sha256sum "$compose.new" | awk '{print $1}')"
        if [[ -n "$oldsum" && "$oldsum" != "$newsum" && ${ALLOW_COMPOSE_CHANGE:=false} != true ]]; then
          log ERROR "Compose checksum changed for $name. Set ALLOW_COMPOSE_CHANGE=true to accept. Keeping existing."
          rm -f "$compose.new"
        else
          mv -f "$compose.new" "$compose"; echo "$newsum" >"$sumfile"
        fi
      fi
      ;;
    git)
      local lockfile="$dir/.locked_ref"
      if [[ -d "$dir/.git" ]]; then
        if [[ ${ACTION:=install} == update ]]; then
          log INFO "Updating git repo for $name"; (cd "$dir" && git fetch --all --tags --prune && git pull --ff-only)
          (cd "$dir" && git rev-parse HEAD) >"$lockfile"
        else
          # Honor existing lock
          if [[ -f "$lockfile" ]]; then
            local ref; ref="$(cat "$lockfile")"; log INFO "Checking out locked ref $ref for $name"; (cd "$dir" && git checkout -q "$ref" || true)
          fi
        fi
      else
        log INFO "Cloning $name from $src"; git clone --depth 1 "$src" "$dir"
        (cd "$dir" && git rev-parse HEAD) >"$lockfile"
      fi
      ;;
    builtin)
      log INFO "Setting up $name via builtin"
      "$src"
      ;;
    *) log ERROR "Unknown service type: $type"; exit 1;;
  esac

  # Optional exposure prompt
  if [[ "$expose_prompt" == "true" && ${EXPOSE:=false} == true ]]; then
    if [[ -f "$dir/docker-compose.yml" ]]; then
      log INFO "Enabling external exposure for $name"
      expose_ports_in_compose "$dir/docker-compose.yml"
      # For crAPI, also set LISTEN_IP=0.0.0.0 in .env so variable-based binds expose correctly
      if [[ "$name" == "crapi" ]]; then
        if grep -q '^LISTEN_IP=' "$dir/.env" 2>/dev/null; then
          sed -i 's/^LISTEN_IP=.*/LISTEN_IP=0.0.0.0/' "$dir/.env"
        else
          echo 'LISTEN_IP=0.0.0.0' >>"$dir/.env"
        fi
      fi
      # For Pixi, keep Mongo ports restricted to loopback for safety
      if [[ "$name" == "pixi" ]]; then
        # Revert any exposed host bindings for container ports 27017 and 28017 back to 127.0.0.1
        sed -E -i '/ports:/,/-/ s/^([[:space:]]*-[[:space:]]*")0\.0\.0\.0:([0-9]+:)(27017\")/\1127.0.0.1:\2\3/' "$dir/docker-compose.yml" || true
        sed -E -i '/ports:/,/-/ s/^([[:space:]]*-[[:space:]]*")0\.0\.0\.0:([0-9]+:)(28017\")/\1127.0.0.1:\2\3/' "$dir/docker-compose.yml" || true
        # Unquoted variant
        sed -E -i '/ports:/,/-/ s/^([[:space:]]*-[[:space:]]*)0\.0\.0\.0:([0-9]+:)(27017)/\1127.0.0.1:\2\3/' "$dir/docker-compose.yml" || true
        sed -E -i '/ports:/,/-/ s/^([[:space:]]*-[[:space:]]*)0\.0\.0\.0:([0-9]+:)(28017)/\1127.0.0.1:\2\3/' "$dir/docker-compose.yml" || true
      fi
    fi
  fi

  log INFO "Pulling images and starting $name"
  if [[ -f "$dir/.force_pull" ]]; then
    # Services that require force pull (like crAPI with build issues)
    log INFO "Force pulling images for $name to avoid build issues"
    (cd "$dir" && sudo $COMPOSE_CMD pull --ignore-pull-failures || true; sudo $COMPOSE_CMD up -d --no-build)
  elif [[ -f "$dir/.allow_build" ]]; then
    # Services with local build contexts: build first to avoid pull errors, then start
    (cd "$dir" && sudo $COMPOSE_CMD build --pull || true; sudo $COMPOSE_CMD up -d)
  else
    (cd "$dir" && sudo $COMPOSE_CMD pull || true; sudo $COMPOSE_CMD up -d --no-build)
  fi

  # Optional post-setup tweaks (after containers are started)
  if [[ -n "$post" ]]; then "$post"; fi
}

start_service() { 
  local name="$1"; local dir="$BASE_DIR/$name"
  if [[ -f "$dir/.force_pull" ]]; then
    (cd "$dir" && sudo $COMPOSE_CMD up -d --no-build)
  elif [[ -f "$dir/.allow_build" ]]; then
    (cd "$dir" && sudo $COMPOSE_CMD up -d)
  else
    (cd "$dir" && sudo $COMPOSE_CMD up -d --no-build)
  fi
}
stop_service()  { local name="$1"; (cd "$BASE_DIR/$name" && sudo $COMPOSE_CMD down); }
clean_service() {
  local name="$1"; local dir="$BASE_DIR/$name"
  if [[ -d "$dir" ]]; then
    (cd "$dir" && sudo $COMPOSE_CMD down --rmi all -v || true)
    sudo rm -rf "$dir"
    log INFO "Cleaned $name"
  else
    log INFO "$name not installed; nothing to clean"
  fi
}

# ---------- service loop ----------
for_each_service() {
  local fn="$1"; shift
  local target="${1:-all}"; shift || true
  local handled=false
  for entry in "${SERVICES[@]}"; do
    eval "$entry" # defines: name type src expose_prompt [post]
    if [[ "$target" == "all" || "$target" == "$name" ]]; then
      "$fn" "$name" "$type" "$src" "$expose_prompt" "${post:-}"
      handled=true
    fi
  done
  if [[ "$handled" == false ]]; then
    log ERROR "Unknown service: $target"; exit 1
  fi
}

# Wrappers for for_each_service with appropriate function signature
install_update_wrapper() { install_or_update_service "$@"; }
start_wrapper()          { local name="$1"; shift 4 || true; start_service "$name"; }
stop_wrapper()           { local name="$1"; shift 4 || true; stop_service "$name"; }
clean_wrapper()          { local name="$1"; shift 4 || true; clean_service "$name"; }
uninstall_wrapper()      { local name="$1"; clean_service "$name"; }

# ---------- dependency bootstrap (optional) ----------
ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log INFO "Installing Docker Engine and Compose (distro packages)"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -yq
    apt-get install -yq docker.io docker-compose || true
  fi
  
  # Install Maven for Security Shepherd and other Java-based services
  if ! command -v mvn >/dev/null 2>&1; then
    log INFO "Installing Maven for Java-based services"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -yq
    apt-get install -yq maven || true
  fi
}

# ---------- CLI ----------
print_help() {
  cat <<EOF
Usage: sudo $0 <action> <service|all> [--expose]
Actions:
  install   Install or update and start services
  update    Update and restart services
  start     Start services
  stop      Stop services
  clean     Remove services and data under $BASE_DIR/<service>
  uninstall Remove a SINGLE service and its data (safer alias of clean; does not allow 'all')

Services:
  crapi, vapi, dvga, juice-shop, webgoat, dvwa, bwapp, security-shepherd, pixi, xvwa, mutillidae, vampi, dvws, lab-dashboard, or 'all'

Flags:
  --expose  Enable external exposure (0.0.0.0 host binding where applicable)
  --force   Skip confirmation prompts for uninstall

Env (advanced):
  ALLOW_COMPOSE_CHANGE=true  Accept upstream compose checksum changes (TOFU)
EOF
}

main() {
  if [[ "$(id -u)" != "0" ]]; then echo "This script must be run as root" >&2; exit 1; fi

  local action="${1:-}"; shift || true
  local target="${1:-all}"; shift || true
  EXPOSE=false
  FORCE=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --expose) EXPOSE=true; shift;;
      --force) FORCE=true; shift;;
      -h|--help) print_help; exit 0;;
      *) log ERROR "Unknown argument: $1"; print_help; exit 1;;
    esac
  done

  ensure_dir "$BASE_DIR"; ensure_docker

  case "$action" in
    install|update)
      ACTION="$action" for_each_service install_update_wrapper "$target"
      ;;
    start)
      for_each_service start_wrapper "$target"
      ;;
    stop)
      for_each_service stop_wrapper "$target"
      ;;
    uninstall)
      # Uninstall only supports a single named service (safer than 'clean all')
      if [[ "$target" == "all" || -z "$target" ]]; then
        log ERROR "'uninstall' requires a single service name (not 'all')."; exit 1
      fi
      if [[ "$FORCE" != true ]]; then
        read -r -p "This will permanently remove containers, images, volumes, and directory $BASE_DIR/$target. Continue? [y/N] " ans
        if [[ ! "$ans" =~ ^[Yy]$ ]]; then
          log INFO "Uninstall of $target aborted by user"; exit 1
        fi
      fi
      local __t0=$SECONDS
      uninstall_wrapper "$target" "" "" "" ""
      local __dt=$(( SECONDS - __t0 ))
      log INFO "Uninstalled $target and removed $BASE_DIR/$target (took ${__dt}s)"
      ;;
    clean)
      for_each_service clean_wrapper "$target"
      ;;
    *) print_help; exit 1;;
  esac

  log INFO "Done."
}

main "$@"

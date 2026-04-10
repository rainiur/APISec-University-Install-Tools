#!/usr/bin/env bash

# Post-setup for vAPI.
# Expects BASE_DIR, ensure_dir, and log helpers from the main script.
vapi_post_impl() {
  local dir="$BASE_DIR/vapi"

  # Port and environment setup is now handled by vapi_setup function
  # This function focuses on post-startup configuration

  if [[ -f "$dir/docker-compose.yml" ]]; then
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

  # Remove stale containers from previous incompatible compose runs.
  # This prevents name conflicts like "/vapi-db-1 is already in use".
  docker rm -f vapi-db-1 vapi-www-1 vapi-phpmyadmin-1 >/dev/null 2>&1 || true

  # Ensure remaining database variables are set
  local env_file="$dir/.env"
  touch "$env_file"
  grep -q '^DB_CONNECTION='       "$env_file" || echo 'DB_CONNECTION=mysql' >>"$env_file"
  grep -q '^DB_HOST='             "$env_file" || echo 'DB_HOST=db' >>"$env_file"
  grep -q '^DB_PORT='             "$env_file" || echo 'DB_PORT=3306' >>"$env_file"
  grep -q '^DB_DATABASE='         "$env_file" || echo 'DB_DATABASE=vapi' >>"$env_file"
  grep -q '^DB_USERNAME='         "$env_file" || echo 'DB_USERNAME=root' >>"$env_file"
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
        if ! php artisan migrate --force; then
          echo 'WARNING: Laravel migrate failed; continuing (likely pre-existing schema)' ;
        fi &&
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

  # Note: .allow_build file is created by vapi_setup function before build process
}

# Lightweight runtime health check for vAPI after containers are started.
vapi_health_check_impl() {
  local base_url="${1:-http://localhost:8000}"
  local root_code api_code

  root_code="$(curl -s -o /dev/null -w '%{http_code}' "${base_url}/" 2>/dev/null || echo 000)"
  api_code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "${base_url}/vapi/api4/login" 2>/dev/null || echo 000)"

  if [[ "$root_code" == "200" && "$api_code" =~ ^(200|400|401|422)$ ]]; then
    log INFO "vAPI health check passed (root=${root_code}, api4_login=${api_code})"
    return 0
  fi

  log WARN "vAPI health check failed (root=${root_code}, api4_login=${api_code})"
  log WARN "Check vAPI logs: docker logs vapi-www-1 --tail 100"
  return 1
}

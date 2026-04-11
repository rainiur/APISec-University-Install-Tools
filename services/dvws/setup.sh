#!/usr/bin/env bash

# Source-based setup for DVWS Node.
# Expects BASE_DIR, ensure_dir, and write_env_port from the main script.
dvws_setup_impl() {
  local dir="$BASE_DIR/dvws"
  ensure_dir "$dir"
  write_env_port "$dir" DVWS_PORT 8087

  local env_file="$dir/.env"
  touch "$env_file"
  if grep -q '^DVWS_GRAPHQL_PORT=' "$env_file"; then
    sed -i 's|^DVWS_GRAPHQL_PORT=.*|DVWS_GRAPHQL_PORT=4000|' "$env_file"
  else
    echo 'DVWS_GRAPHQL_PORT=4000' >> "$env_file"
  fi
  if grep -q '^DVWS_SOAP_PORT=' "$env_file"; then
    sed -i 's|^DVWS_SOAP_PORT=.*|DVWS_SOAP_PORT=9090|' "$env_file"
  else
    echo 'DVWS_SOAP_PORT=9090' >> "$env_file"
  fi
  if grep -q '^DVWS_SUBNET=' "$env_file"; then
    sed -i 's|^DVWS_SUBNET=.*|DVWS_SUBNET=172.41.0.0/24|' "$env_file"
  else
    echo 'DVWS_SUBNET=172.41.0.0/24' >> "$env_file"
  fi
  if grep -q '^DVWS_MONGO_IMAGE=' "$env_file"; then
    sed -i 's|^DVWS_MONGO_IMAGE=.*|DVWS_MONGO_IMAGE=mongo:4.0.4|' "$env_file"
  else
    echo 'DVWS_MONGO_IMAGE=mongo:4.0.4' >> "$env_file"
  fi
  if grep -q '^DVWS_MYSQL_IMAGE=' "$env_file"; then
    sed -i 's|^DVWS_MYSQL_IMAGE=.*|DVWS_MYSQL_IMAGE=mysql:8.0|' "$env_file"
  else
    echo 'DVWS_MYSQL_IMAGE=mysql:8.0' >> "$env_file"
  fi

  cat >"$dir/docker-compose.yml" <<'EOF'
services:
  dvws-mongo:
    image: ${DVWS_MONGO_IMAGE:-mongo:4.0.4}
    restart: unless-stopped
    networks:
      - dvws
  dvws-mysql:
    image: ${DVWS_MYSQL_IMAGE:-mysql:8.0}
    environment:
      - MYSQL_ROOT_PASSWORD=mysecretpassword
      - MYSQL_DATABASE=dvws_sqldb
    restart: unless-stopped
    networks:
      - dvws
  web:
    build:
      context: .
    ports:
      - "${DVWS_PORT:-8087}:80"
      - "127.0.0.1:${DVWS_GRAPHQL_PORT:-4000}:4000"
      - "127.0.0.1:${DVWS_SOAP_PORT:-9090}:9090"
    environment:
      - WAIT_HOSTS=dvws-mysql:3306,dvws-mongo:27017
      - WAIT_HOSTS_TIMEOUT=160
      - SQL_LOCAL_CONN_URL=dvws-mysql
      - MONGO_LOCAL_CONN_URL=mongodb://dvws-mongo:27017/node-dvws
    depends_on:
      - dvws-mongo
      - dvws-mysql
    networks:
      - dvws
    restart: unless-stopped
networks:
  dvws:
    ipam:
      config:
        - subnet: ${DVWS_SUBNET:-172.41.0.0/24}
EOF

  touch "$dir/.allow_build"
}

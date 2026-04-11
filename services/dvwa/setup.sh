#!/usr/bin/env bash

# Built-in setup for DVWA.
# Expects BASE_DIR, ensure_dir, and write_env_port from the main script.
setup_dvwa_impl() {
  local dir="$BASE_DIR/dvwa"
  ensure_dir "$dir"
  write_env_port "$dir" DVWA_PORT 8081

  local env_file="$dir/.env"
  touch "$env_file"
  if grep -q '^DVWA_IMAGE=' "$env_file"; then
    sed -i 's|^DVWA_IMAGE=.*|DVWA_IMAGE=ghcr.io/digininja/dvwa:latest|' "$env_file"
  else
    echo 'DVWA_IMAGE=ghcr.io/digininja/dvwa:latest' >> "$env_file"
  fi
  if grep -q '^DVWA_SUBNET=' "$env_file"; then
    sed -i 's|^DVWA_SUBNET=.*|DVWA_SUBNET=172.40.0.0/24|' "$env_file"
  else
    echo 'DVWA_SUBNET=172.40.0.0/24' >> "$env_file"
  fi

  cat >"$dir/docker-compose.yml" <<'EOF'
services:
  dvwa:
    image: ${DVWA_IMAGE:-ghcr.io/digininja/dvwa:latest}
    ports:
      - "${DVWA_PORT:-8081}:80"
    environment:
      - DB_SERVER=db
      - DB_USER=dvwa
      - DB_PASSWORD=dvwa
      - DB_DATABASE=dvwa
    depends_on:
      - db
    networks:
      - dvwa
    restart: unless-stopped
  db:
    image: docker.io/library/mariadb:10
    environment:
      - MYSQL_ROOT_PASSWORD=dvwa
      - MYSQL_DATABASE=dvwa
      - MYSQL_USER=dvwa
      - MYSQL_PASSWORD=dvwa
    volumes:
      - dvwa-db:/var/lib/mysql
    networks:
      - dvwa
    restart: unless-stopped
networks:
  dvwa:
    ipam:
      config:
        - subnet: ${DVWA_SUBNET:-172.40.0.0/24}
volumes:
  dvwa-db:
EOF
}

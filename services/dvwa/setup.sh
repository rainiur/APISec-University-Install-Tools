#!/usr/bin/env bash

# Built-in setup for DVWA.
# Expects BASE_DIR, ensure_dir, and write_env_port from the main script.
setup_dvwa_impl() {
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

#!/usr/bin/env bash

# Built-in setup for Mutillidae.
# Expects BASE_DIR, ensure_dir, write_env_port, and log from the main script.
setup_mutillidae_impl() {
  local dir="$BASE_DIR/mutillidae"
  ensure_dir "$dir"
  write_env_port "$dir" MUTILLIDAE_PORT 8088
  write_env_port "$dir" MUTILLIDAE_HTTPS_PORT 18088

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
      - "${MUTILLIDAE_HTTPS_PORT:-18088}:443"
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

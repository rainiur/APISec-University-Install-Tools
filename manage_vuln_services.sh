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
  "name=crapi type=compose_url src=https://raw.githubusercontent.com/OWASP/crAPI/main/deploy/docker/docker-compose.yml expose_prompt=true"
  "name=vapi type=git src=https://github.com/roottusk/vapi.git expose_prompt=false post=vapi_post"
  "name=dvga type=builtin src=setup_dvga expose_prompt=true"
  "name=juice-shop type=builtin src=setup_juice_shop expose_prompt=false"
)

# ---------- helpers ----------
ensure_dir() { local d="$1"; [[ -d "$d" ]] || { log INFO "Creating $d"; mkdir -p "$d"; }; }

is_installed() { local svc="$1"; [[ -f "$BASE_DIR/$svc/docker-compose.yml" ]] || [[ -d "$BASE_DIR/$svc/.git" ]]; }

# Safer targeted exposure changer: only change host binding in ports entries
expose_ports_in_compose() {
  local compose_file="$1"
  # Replace only patterns like "- \"127.0.0.1:PORT:...\"" with 0.0.0.0
  sed -E -i '/ports:/,/-/ s/^([[:space:]]*-[[:space:]]*)"127\.0\.0\.1:([0-9]+:)/\10.0.0.0:\2/' "$compose_file"
}

# ---------- built-in setups ----------
setup_juice_shop() {
  local dir="$BASE_DIR/juice-shop"
  ensure_dir "$dir"
  cat >"$dir/docker-compose.yml" <<'EOF'
services:
  juice-shop:
    image: bkimminich/juice-shop
    ports:
      - "3000:3000"
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
  cat >"$dir/docker-compose.yml" <<EOF
services:
  dvga:
    build:
      context: $dir
      dockerfile: Dockerfile
    image: dvga
    container_name: dvga
    ports:
      - "5013:5013"
    environment:
      - WEB_HOST=127.0.0.1
    restart: unless-stopped
EOF
}

vapi_post() {
  local dir="$BASE_DIR/vapi"
  # Some upstream compose files bind 80:80; prefer 8000:80 locally
  if [[ -f "$dir/docker-compose.yml" ]]; then
    sed -i 's/\b80:80\b/8000:80/g' "$dir/docker-compose.yml" || true
  fi
}

# ---------- core actions ----------
install_or_update_service() {
  local name="$1"; local type="$2"; local src="$3"; local expose_prompt="$4"; local post="${5:-}"
  local dir="$BASE_DIR/$name"
  ensure_dir "$dir"

  case "$type" in
    compose_url)
      if [[ ! -f "$dir/docker-compose.yml" ]]; then
        log INFO "Downloading compose for $name"
      else
        log INFO "Updating compose for $name"
      fi
      curl -fsSL -o "$dir/docker-compose.yml" "$src"
      ;;
    git)
      if [[ -d "$dir/.git" ]]; then
        log INFO "Updating git repo for $name"; (cd "$dir" && git pull --ff-only)
      else
        log INFO "Cloning $name from $src"; git clone "$src" "$dir"
      fi
      ;;
    builtin)
      log INFO "Setting up $name via builtin"
      "$src"
      ;;
    *) log ERROR "Unknown service type: $type"; exit 1;;
  esac

  # Optional post-setup tweaks
  if [[ -n "$post" ]]; then "$post"; fi

  # Optional exposure prompt
  if [[ "$expose_prompt" == "true" && ${EXPOSE:=false} == true ]]; then
    if [[ -f "$dir/docker-compose.yml" ]]; then
      log INFO "Enabling external exposure for $name"
      expose_ports_in_compose "$dir/docker-compose.yml"
    fi
  fi

  log INFO "Pulling images and starting $name"
  (cd "$dir" && sudo $COMPOSE_CMD pull || true; sudo $COMPOSE_CMD up -d)
}

start_service() { local name="$1"; (cd "$BASE_DIR/$name" && sudo $COMPOSE_CMD up -d); }
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

# ---------- dependency bootstrap (optional) ----------
ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log INFO "Installing Docker Engine and Compose (distro packages)"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -yq
    apt-get install -yq docker.io docker-compose || true
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

Services:
  crapi, vapi, dvga, juice-shop, or 'all'

Flags:
  --expose  Enable external exposure (0.0.0.0 host binding where applicable)
EOF
}

main() {
  if [[ "$(id -u)" != "0" ]]; then echo "This script must be run as root" >&2; exit 1; fi

  local action="${1:-}"; shift || true
  local target="${1:-all}"; shift || true
  EXPOSE=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --expose) EXPOSE=true; shift;;
      -h|--help) print_help; exit 0;;
      *) log ERROR "Unknown argument: $1"; print_help; exit 1;;
    esac
  done

  ensure_dir "$BASE_DIR"; ensure_docker

  case "$action" in
    install|update)
      for_each_service install_update_wrapper "$target"
      ;;
    start)
      for_each_service start_wrapper "$target"
      ;;
    stop)
      for_each_service stop_wrapper "$target"
      ;;
    clean)
      for_each_service clean_wrapper "$target"
      ;;
    *) print_help; exit 1;;
  esac

  log INFO "Done."
}

main "$@"

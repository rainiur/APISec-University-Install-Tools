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

# Resolve script directory once so module paths remain valid after cd operations.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
  "name=vapi type=git src=https://github.com/roottusk/vapi.git expose_prompt=false post=vapi_post setup=vapi_setup"
  "name=dvga type=builtin src=setup_dvga expose_prompt=true"
  "name=juice-shop type=git src=https://github.com/juice-shop/juice-shop.git expose_prompt=false setup=juice_shop_setup"
  # Additional vulnerable apps
  "name=webgoat type=builtin src=setup_webgoat expose_prompt=false post=webgoat_post"
  "name=dvwa type=builtin src=setup_dvwa expose_prompt=false"
  "name=bwapp type=builtin src=setup_bwapp expose_prompt=false"
  "name=security-shepherd type=git src=https://github.com/OWASP/SecurityShepherd.git expose_prompt=false post=security_shepherd_post setup=security_shepherd_setup db_init=security_shepherd_db_init"
  "name=pixi type=git src=https://github.com/DevSlop/Pixi.git expose_prompt=true post=pixi_post setup=pixi_setup"
  "name=xvwa type=builtin src=setup_xvwa expose_prompt=false"
  "name=mutillidae type=builtin src=setup_mutillidae expose_prompt=false post=mutillidae_post"
  "name=vampi type=git src=https://github.com/erev0s/VAmPI.git expose_prompt=false post=vampi_post setup=vampi_setup"
  "name=dvws type=git src=https://github.com/snoopysecurity/dvws-node.git expose_prompt=false post=dvws_post setup=dvws_setup"
  "name=lab-dashboard type=builtin src=setup_lab_dashboard expose_prompt=false"
)

# ---------- helpers ----------
ensure_dir() { local d="$1"; [[ -d "$d" ]] || { log INFO "Creating $d"; mkdir -p "$d"; }; }
write_env_port() { # write or ensure PORT env var in .env
  local dir="$1"; local var="$2"; local val="$3";
  ensure_dir "$dir"
  grep -q "^${var}=" "$dir/.env" 2>/dev/null && sed -i "s/^${var}=.*/${var}=${val}/" "$dir/.env" || echo "${var}=${val}" >>"$dir/.env";
}

# Security Shepherd post-setup (runs after containers start)
security_shepherd_post() {
  local module_file="$SCRIPT_DIR/services/security-shepherd/post.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  security_shepherd_post_impl
}

security_shepherd_db_init() {
  local module_file="$SCRIPT_DIR/services/security-shepherd/post.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  security_shepherd_db_init_impl
}

# Fix crAPI gateway healthcheck and handle Docker build issues
crapi_post() {
  local module_file="$SCRIPT_DIR/services/crapi/post.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  crapi_post_impl
}

# Fix WebGoat healthcheck (curl missing); use wget
webgoat_post() {
  local module_file="$SCRIPT_DIR/services/webgoat/post.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  webgoat_post_impl
}

# Pixi post-setup (runs after containers start) - most configuration now handled by pixi_setup
pixi_post() {
  local module_file="$SCRIPT_DIR/services/pixi/post.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  pixi_post_impl
}

# Early setup for VAmPI to create .allow_build before build process
vampi_setup() {
  local module_file="$SCRIPT_DIR/services/vampi/setup.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  vampi_setup_impl
}

# Normalize VAmPI to host 8086; prefer container 5000 if present, else 80
vampi_post() {
  local module_file="$SCRIPT_DIR/services/vampi/post.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  vampi_post_impl
}

# Normalize DVWS to host 8087 (container 80)
dvws_post() {
  local module_file="$SCRIPT_DIR/services/dvws/post.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  dvws_post_impl
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
juice_shop_setup() {
  local module_file="$SCRIPT_DIR/services/juice-shop/setup.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  juice_shop_setup_impl
}

setup_dvga() {
  local module_file="$SCRIPT_DIR/services/dvga/setup.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  setup_dvga_impl
}

setup_webgoat() {
  local module_file="$SCRIPT_DIR/services/webgoat/setup.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  setup_webgoat_impl
}

setup_dvwa() {
  local module_file="$SCRIPT_DIR/services/dvwa/setup.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  setup_dvwa_impl
}

setup_bwapp() {
  local module_file="$SCRIPT_DIR/services/bwapp/setup.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  setup_bwapp_impl
}

setup_xvwa() {
  local module_file="$SCRIPT_DIR/services/xvwa/setup.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  setup_xvwa_impl
}

setup_mutillidae() {
  local module_file="$SCRIPT_DIR/services/mutillidae/setup.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  setup_mutillidae_impl
}

# Post-setup function for Mutillidae to initialize database
mutillidae_post() {
  local module_file="$SCRIPT_DIR/services/mutillidae/post.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  mutillidae_post_impl
}

dvws_setup() {
  local module_file="$SCRIPT_DIR/services/dvws/setup.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  dvws_setup_impl
}

# Early setup for vAPI to create .allow_build and fix warnings before build process
vapi_setup() {
  local module_file="$SCRIPT_DIR/services/vapi/setup.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  vapi_setup_impl
}

# Early setup for Security Shepherd to fix image references before build process  
security_shepherd_setup() {
  local module_file="$SCRIPT_DIR/services/security-shepherd/setup.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  security_shepherd_setup_impl
}

# Early setup for Pixi to create .allow_build and fix port conflicts before build process
pixi_setup() {
  local module_file="$SCRIPT_DIR/services/pixi/setup.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  pixi_setup_impl
}

setup_lab_dashboard() {
  local module_file="$SCRIPT_DIR/services/lab-dashboard/setup.sh"
  if [[ ! -f "$module_file" ]]; then
  log ERROR "Missing module: $module_file"
  return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  setup_lab_dashboard_impl
}

vapi_post() {
  local module_file="$SCRIPT_DIR/services/vapi/post.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  vapi_post_impl
}

vapi_health_check() {
  local module_file="$SCRIPT_DIR/services/vapi/post.sh"
  if [[ ! -f "$module_file" ]]; then
    log ERROR "Missing module: $module_file"
    return 1
  fi
  # shellcheck source=/dev/null
  source "$module_file"
  vapi_health_check_impl "http://localhost:${VAPI_PORT:-8000}"
}

# ---------- core actions ----------
install_or_update_service() {
  local name="$1"; local type="$2"; local src="$3"; local expose_prompt="$4"; local post="${5:-}"; local setup="${6:-}"; local db_init="${7:-}"
  local dir="$BASE_DIR/$name"
  ensure_dir "$BASE_DIR"

  case "$type" in
    compose_url)
      ensure_dir "$dir"
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
        if [[ -f "$dir/.git/index.lock" ]]; then
          log WARN "Removing stale git lock for $name"
          rm -f "$dir/.git/index.lock"
        fi
        if [[ ${ACTION:=install} == update ]]; then
          log INFO "Updating git repo for $name"; (cd "$dir" && git fetch --all --tags --prune && git pull --ff-only)
          (cd "$dir" && git rev-parse HEAD) >"$lockfile"
        else
          # Honor existing lock
          if [[ -f "$lockfile" ]]; then
            local ref
            ref="$(cat "$lockfile")"
            log INFO "Checking out locked ref $ref for $name"
            # Reconcile repositories that have tracked files staged/removed from prior interrupted runs.
            (cd "$dir" && git reset --hard HEAD >/dev/null 2>&1 || true)
            (cd "$dir" && git clean -fdx >/dev/null 2>&1 || true)
            (cd "$dir" && git checkout -q -f "$ref" || true)
          fi
        fi
      else
        if [[ -e "$dir" ]]; then
          log INFO "Resetting $dir for fresh clone"
          rm -rf "$dir"
        fi
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

  # Optional early setup function (runs before build process)
  if [[ -n "$setup" ]]; then "$setup"; fi

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

  # VAmPI: run post before compose up so port normalization (8086/8093) is applied before containers start
  if [[ "$name" == "vampi" && -n "$post" ]]; then "$post"; fi

  local compose_file="$dir/docker-compose.yml"
  if [[ ! -f "$compose_file" && -f "$dir/docker-compose.yaml" ]]; then
    compose_file="$dir/docker-compose.yaml"
  fi
  if [[ ! -f "$compose_file" ]]; then
    log ERROR "No docker compose file found for $name in $dir"
    return 1
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

  # Optional DB initialisation (after post, waits for DB readiness)
  if [[ -n "$db_init" ]]; then "$db_init"; fi
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
stop_service()  { 
  local name="$1"; local dir="$BASE_DIR/$name"
  if [[ -d "$dir" ]]; then
    # Check if docker-compose file exists
    if [[ -f "$dir/docker-compose.yml" ]] || [[ -f "$dir/docker-compose.yaml" ]]; then
      (cd "$dir" && sudo $COMPOSE_CMD down)
    else
      log INFO "$name directory exists but no docker-compose file found; nothing to stop"
    fi
  else
    log INFO "$name not installed; nothing to stop"
  fi
}
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
    # Use a subshell to completely isolate variables and immediately execute if matched
    if (
      eval "$entry" # defines: name type src expose_prompt [post] [setup] [db_init]
      if [[ "$target" == "all" || "$target" == "$name" ]]; then
        "$fn" "$name" "$type" "$src" "$expose_prompt" "${post:-}" "${setup:-}" "${db_init:-}"
        exit 0  # Signal success to parent shell
      else
        exit 1  # Signal no match to parent shell
      fi
    ); then
      handled=true
    fi
  done
  if [[ "$handled" == false ]]; then
    log ERROR "Unknown service: $target"; exit 1
  fi
}

# Wrappers for for_each_service with appropriate function signature
install_update_wrapper() { install_or_update_service "$@"; }
start_wrapper() {
  local name="$1"; local db_init="${7:-}"
  start_service "$name"

  # Run DB initialisation if defined for this service
  if [[ -n "$db_init" ]]; then "$db_init"; fi

  # Run lightweight vAPI runtime check after start without impacting other services.
  if [[ "$name" == "vapi" ]]; then
    vapi_health_check || true
  fi
}
stop_wrapper()           { local name="$1"; shift 6 || true; stop_service "$name"; }
clean_wrapper()          { local name="$1"; clean_service "$name"; }
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

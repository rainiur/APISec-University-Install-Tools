#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
export DEBIAN_FRONTEND=noninteractive

log() { printf '[%(%FT%TZ)T] %s\n' -1 "$*"; }
trap 'log "ERROR at line $LINENO"; exit 1' ERR

# ------------------------------------------------------------
# Uninstall mode (remove tools installed by this script)
# Usage: sudo bash apisec_tool_install.sh uninstall [--force] [--purge]
#  --force : skip confirmation
#  --purge : also remove Docker data (/var/lib/docker) and apt repo list
ACTION="${1:-}"
if [[ "$ACTION" == "uninstall" ]]; then
  shift || true
  FORCE=false; PURGE=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) FORCE=true; shift;;
      --purge) PURGE=true; shift;;
      *) break;;
    esac
  done
  if [[ "$FORCE" != true ]]; then
    read -r -p "This will uninstall Docker CE, ZAP, Postman, jwt_tool, kiterunner, pipx tools, and Jython from this system. Continue? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { log "Uninstall aborted"; exit 1; }
  fi
  . /etc/os-release || true
  log "Stopping Docker if running..."; sudo systemctl stop docker 2>/dev/null || true
  log "Removing apt packages (Docker CE and ZAP)..."
  sudo apt-get remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin zaproxy || true
  # Remove distro-provided docker.io if present
  sudo apt-get remove -y docker.io docker-cli containerd runc || true
  # Remove Arjun via apt on Kali if present
  if [[ "${ID:-}" == "kali" ]]; then sudo apt-get remove -y arjun || true; fi
  log "Uninstalling pipx apps (mitmproxy2swagger, arjun) if present..."
  pipx uninstall mitmproxy2swagger || true
  pipx uninstall arjun || true
  log "Removing Postman, jwt_tool, kiterunner, Jython artifacts..."
  sudo rm -f /usr/bin/postman /usr/bin/jwt_tool /usr/bin/kr /usr/bin/zap || true
  sudo rm -rf /opt/Postman /opt/jwt_tool /opt/kiterunner || true
  sudo rm -f /opt/jython-standalone-2.7.3.jar || true
  if [[ "$PURGE" == true ]]; then
    log "Purging Docker data under /var/lib/docker (destructive)..."
    sudo rm -rf /var/lib/docker || true
    log "Removing Docker APT repo list..."
    sudo rm -f /etc/apt/sources.list.d/docker.list || true
  fi
  log "Autoremoving unused dependencies..."
  sudo apt-get -f install -y || true
  sudo apt-get autoremove -y || true
  log "Uninstall complete."
  exit 0
fi

log "Updating system packages..."
# Pre-clean invalid Docker repo if previously added (e.g., Ubuntu repo on Kali)
. /etc/os-release || true
if [[ "${ID:-}" == "kali" ]] && [[ -f /etc/apt/sources.list.d/docker.list ]] && \
   grep -q 'download.docker.com/linux/ubuntu' /etc/apt/sources.list.d/docker.list; then
  sudo mv /etc/apt/sources.list.d/docker.list \
          /etc/apt/sources.list.d/docker.list.invalid.$(date +%s).bak || true
fi
sudo apt-get update -y
sudo apt-get -o Dpkg::Options::="--force-confnew" -o Dpkg::Options::="--force-confdef" dist-upgrade -y
sudo apt-get autoremove -y

log "Installing prerequisites..."
sudo apt-get install -y git zsh make python3 python3-pip pipx ca-certificates curl gnupg unzip
# Ensure Firefox is available; prefer firefox-esr on Debian/Kali. Skip if already installed.
if ! command -v firefox >/dev/null 2>&1; then
    if apt-cache policy firefox-esr 2>/dev/null | grep -q "Candidate:"; then
        sudo apt-get install -y firefox-esr
    elif apt-cache policy firefox 2>/dev/null | grep -q "Candidate:"; then
        sudo apt-get install -y firefox
    else
        log "Firefox package not found in APT; it may be installed via Snap/Flatpak or already present."
    fi
fi
pipx ensurepath || true

if [ ! -f /opt/jython-standalone-2.7.3.jar ]; then
    log "Installing Jython 2.7.3..."
    tmp_jy=$(mktemp)
    wget --https-only --timeout=30 --tries=3 -O "$tmp_jy" "https://repo1.maven.org/maven2/org/python/jython-standalone/2.7.3/jython-standalone-2.7.3.jar"
    # TODO: Verify checksum/signature before moving to /opt
    sudo install -m 0644 "$tmp_jy" /opt/jython-standalone-2.7.3.jar
    rm -f "$tmp_jy"
fi

log "FoxyProxy: ensure extension is installed"
echo "Add Foxy Proxy extension and configure proxies:"
echo "BurpSuite 127.0.0.1 Port 8080"
echo "Postman 127.0.0.1 Port 5555"
echo "$HOME"
found="$(find "$HOME/.mozilla/" -type f -name "foxyproxy*.xpi" 2>/dev/null || true)"
echo "$found"
if [ -z "$found" ]; then
    tmpxpi=$(mktemp)
    wget --https-only --timeout=30 --tries=3 -O "$tmpxpi" "https://addons.mozilla.org/firefox/downloads/file/4212976/foxyproxy_standard-8.8.xpi"
    firefox -install-addon "$tmpxpi" || true
    rm -f "$tmpxpi"
fi

log "BurpSuite: Skipping GUI launch during install. See README for Autorize + Jython config."

cd /opt

if [ ! -x /opt/Postman/Postman ]; then
    echo "Create account and log into Postman and create a new workspace"
    log "Installing Postman..."
    tmp_tgz=$(mktemp)
    wget --https-only --timeout=30 --tries=3 -O "$tmp_tgz" https://dl.pstmn.io/download/latest/linux64
    sudo rm -rf /opt/Postman
    sudo tar -xzf "$tmp_tgz" -C /opt
    sudo ln -sf /opt/Postman/Postman /usr/bin/postman
    rm -f "$tmp_tgz"
fi

log "Installing mitmproxy2swagger via pipx..."
pipx install mitmproxy2swagger --force || true

log "Installing Docker (official repository)..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
# Detect distro and set correct Docker repo (Ubuntu/Debian). Map Kali to Debian/bookworm.
. /etc/os-release
DOCKER_OS="ubuntu"
DOCKER_CODENAME="$VERSION_CODENAME"
case "$ID" in
  ubuntu)
    DOCKER_OS="ubuntu"; DOCKER_CODENAME="$VERSION_CODENAME";;
  debian)
    DOCKER_OS="debian"; DOCKER_CODENAME="$VERSION_CODENAME";;
  kali)
    DOCKER_OS="debian"; DOCKER_CODENAME="bookworm";;
  *)
    DOCKER_OS="debian"; DOCKER_CODENAME="bookworm";;
esac
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DOCKER_OS $DOCKER_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update -y
# Remove potentially conflicting distro packages that ship the same plugin paths
sudo apt-get remove -y docker-buildx docker-compose || true
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin golang-go zaproxy
sudo usermod -aG docker "$USER" || true

sudo ln -sf /usr/share/zaproxy/zap.sh /usr/bin/zap
zap -cmd -addonupdate || true
zap -cmd -addoninstall openapi || true

# Add hapihacker user
if ! id -u hapihacker >/dev/null 2>&1; then
    log "Creating user hapihacker"
    sudo useradd -m -s /bin/zsh -G sudo hapihacker
    echo 'hapihacker:CHANGE_ME' | sudo chpasswd
    sudo chage -d 0 hapihacker
fi

cd /opt
if [ ! -f /opt/jwt_tool/jwt_tool.py ]; then
    log "Installing jwt_tool..."
    sudo git clone https://github.com/ticarpi/jwt_tool /opt/jwt_tool
    python3 -m venv /opt/jwt_tool/.venv
    /opt/jwt_tool/.venv/bin/python -m pip install --upgrade pip
    /opt/jwt_tool/.venv/bin/python -m pip install termcolor cprint pycryptodomex requests
    sudo chmod +x /opt/jwt_tool/jwt_tool.py
    # Create wrapper script for PATH
    sudo tee /usr/bin/jwt_tool >/dev/null <<'EOF'
#!/usr/bin/env bash
exec /opt/jwt_tool/.venv/bin/python /opt/jwt_tool/jwt_tool.py "$@"
EOF
    sudo chmod +x /usr/bin/jwt_tool
fi

if [ ! -f /opt/kiterunner/dist/kr ]; then
    log "Installing kiterunner..."
    cd /opt
    sudo git clone https://github.com/assetnote/kiterunner.git
    cd kiterunner
    sudo make build
    sudo ln -sf /opt/kiterunner/dist/kr /usr/bin/kr
fi

if ! command -v arjun >/dev/null 2>&1; then
    . /etc/os-release || true
    if [[ "${ID:-}" == "kali" ]]; then
        log "Installing Arjun via apt (Kali)..."
        sudo apt-get install -y arjun || { log "apt install arjun failed, falling back to pipx"; pipx install arjun --force || true; }
    else
        log "Installing Arjun via pipx..."
        pipx install arjun --force || true
    fi
fi

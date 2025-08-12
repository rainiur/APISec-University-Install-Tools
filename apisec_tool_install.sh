#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
export DEBIAN_FRONTEND=noninteractive

log() { printf '[%(%FT%TZ)T] %s\n' -1 "$*"; }
trap 'log "ERROR at line $LINENO"; exit 1' ERR

log "Updating system packages..."
sudo apt-get update -y
sudo apt-get -o Dpkg::Options::="--force-confnew" -o Dpkg::Options::="--force-confdef" dist-upgrade -y
sudo apt-get autoremove -y

log "Installing prerequisites..."
sudo apt-get install -y git zsh make python3 python3-pip pipx firefox ca-certificates curl gnupg unzip
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
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update -y
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
    log "Installing Arjun via pipx..."
    pipx install arjun --force || true
fi

# API Security Scripts

I was tediously installing and uninstalling the tools and docker images for the APISec University course after every new start I wanted to make or reinstall of Kali. To make this a little easier I created scripts to do most of the work for me.

## Unified vulnerable lab manager (Docker)

Use `manage_vuln_services.sh` to install, update, start, stop, and clean multiple vulnerable apps/APIs as Docker instances under `/opt/lab/<service>/`.

Supported services and default host ports (non-conflicting):

- crapi (upstream compose; commonly 8888)
- vapi (8000:80)
- dvga (5013:5013)
- juice-shop (3000:3000)
- webgoat (8080:8080)
- dvwa (8081:80)
- bwapp (8082:80)
- security-shepherd (8083:80)
- pixi (8084:80)
- xvwa (8085:80)
- vampi (8086:5000 preferred; fallback 8086:80)
- dvws (8087:80)
- mutillidae (8088:80)

### Usage

Make executable and run with sudo:

```bash
chmod +x manage_vuln_services.sh
sudo ./manage_vuln_services.sh --help
```

Examples:

- Install all (localhost bindings):
```bash
sudo ./manage_vuln_services.sh install all
```

- Install all and expose externally (applies safe host-binding changes where applicable):
```bash
sudo ./manage_vuln_services.sh install all --expose
```

- Update all (accept upstream compose changes via TOFU):
```bash
sudo ALLOW_COMPOSE_CHANGE=true ./manage_vuln_services.sh update all
```

- Start/stop/clean a single service:
```bash
sudo ./manage_vuln_services.sh start dvga
sudo ./manage_vuln_services.sh stop dvga
sudo ./manage_vuln_services.sh clean dvga
```

### Port customization

Each service writes a `.env` with a service-specific port variable. Change the value and restart the service.

Examples:

- `/opt/lab/webgoat/.env` contains `WEBGOAT_PORT=8080`
- `/opt/lab/vapi/.env` contains `VAPI_PORT=8000`

### Supply-chain hardening (TOFU)

- Git services (e.g., `vapi`, `security-shepherd`, `pixi`, `vampi`, `dvws`) are pinned at first install by commit (`.locked_ref`). Use `update` to refresh and re-pin.
- Compose URL services (e.g., `crapi`) store a checksum (`.compose.sha256`). If upstream changes, set `ALLOW_COMPOSE_CHANGE=true` to accept the new compose.

### Security note

These apps are intentionally vulnerable. Do not expose them to the internet. Use `--expose` only in isolated lab networks.

## Legacy script

`apisec_tool_install.sh` installs desktop tooling (Burp, ZAP, Postman, etc.). The Docker management scripts have been consolidated into `manage_vuln_services.sh`. The previous scripts `manage_docker_builds.sh` and `manage_crapi_vapi_builds.sh` are deprecated and removed.


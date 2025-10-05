# API Security Scripts

I was tediously installing and uninstalling the tools and docker images for the APISec University course after every new start I wanted to make or reinstall of Kali. To make this a little easier I created scripts to do most of the work for me.

## Order of Operations (Do this first)

1) Run tooling installer to set up prerequisites (Docker CE, ZAP, Postman link, jwt_tool, kiterunner, pipx apps, etc.).

```bash
chmod +x apisec_tool_install.sh
sudo ./apisec_tool_install.sh
```

2) Use the vulnerable lab manager to install/update/start the lab services.

```bash
chmod +x manage_vuln_services.sh
sudo ./manage_vuln_services.sh install all
sudo ./manage_vuln_services.sh start webgoat
```

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
- pixi (18000:8000, 18090:8090, 27018:27017, 28018:28017)
- xvwa (8085:80)
- vampi (8086:5000 preferred; fallback 8086:80)
- dvws (8087:80)
- mutillidae (8088:80)
- lab-dashboard (80:80)

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

## Lab Dashboard

The `lab-dashboard` service provides a web interface to access all vulnerable applications:

- **Categorized Services**: API Security, Web Application Security, Specialized Security Testing
- **Direct Access Links**: One-click access to each service
- **External Resources**: GitHub repositories, project websites, Docker Hub links
- **Service Information**: Port numbers and descriptions for each application
- **Responsive Design**: Modern, mobile-friendly interface

Access the dashboard at `http://<server-ip>:80` after installing the `lab-dashboard` service.

## Prerequisites

- Docker Engine + Docker Compose plugin
- Maven (automatically installed by the script)
- Linux host with sudo
- Internet access for first-time pulls/clones

## Quickstart

Recommended sequence:

```bash
# 1) Install desktop tooling and Docker prerequisites
chmod +x apisec_tool_install.sh
sudo ./apisec_tool_install.sh

# 2) Manage vulnerable services
chmod +x manage_vuln_services.sh
sudo ./manage_vuln_services.sh install all
sudo ./manage_vuln_services.sh start webgoat
```

## Flags

- `--expose` Enable external exposure (0.0.0.0 host binding where applicable). Defaults to loopback only.
- `--force`  Skip confirmation prompts (currently used by `uninstall`).

## Actions

- `install`  Install or update and start services
- `update`   Update and restart services
- `start`    Start services
- `stop`     Stop services
- `clean`    Remove services and data under `/opt/lab/<service>` (supports `all`)
- `uninstall <service>` Remove a single service (containers/images/volumes + `/opt/lab/<service>`). Prompts for confirmation unless `--force`.

## Directory layout

Each service is managed under `/opt/lab/<service>/` and typically contains:

- `.env`            Service-specific ports and settings
- `docker-compose.yml` or `.yaml`
- Optional `.compose.sha256` (TOFU) and `.locked_ref` (pinned git ref)
- Optional `.allow_build` marker to permit local image builds
- Service artifacts (cloned sources, configs, volumes)

## vAPI Requirements Compliance

The vAPI installation now fully complies with the official requirements:

**✅ Requirements Met:**
- **PHP**: Handled via Docker container with PHP/Laravel environment
- **MySQL**: Automatic database setup with schema import
- **Postman**: Collections and environment files created automatically
- **MITM Proxy**: Available for testing (not auto-configured)

**✅ Installation Methods:**
- **Docker**: `docker-compose up -d` (fully automated)
- **Database Setup**: Automatic `vapi.sql` import
- **Laravel Setup**: Automatic `php artisan` commands (migrate, seed, key:generate)
- **Postman Setup**: Collections and environment files in `/opt/lab/vapi/postman/`

**✅ Usage:**
- Access API at: `http://localhost:8000`
- Documentation at: `http://localhost:8000/docs`
- Postman collections ready for import

**📋 Optional Helm Support:**
- Helm chart available in vAPI repository (`vapi-chart` folder)
- Requires Kubernetes cluster with Helm installed
- Create secret named `vapi` with `DB_PASSWORD` and `DB_USERNAME`
- Sample command: `helm upgrade --install vapi ./vapi-chart --values=./vapi-chart/values.yaml`

## Service notes

- `crapi`
  - Uses upstream compose. Healthcheck override uses wget-based probe. Gateway service auto-detected.
  - If upstream compose changes, set `ALLOW_COMPOSE_CHANGE=true` on `update`.

- `vapi`
  - Enhanced setup with database schema import and Laravel initialization.
  - Automatic database initialization with `vapi.sql` import.
  - Laravel migrations and seeding handled automatically.
  - Postman collections and environment files created automatically.
  - Local build supported. Script creates `.allow_build` when `build:` is present.
  - Host port via `/opt/lab/vapi/.env` `VAPI_PORT`.
  - Setup instructions available in `/opt/lab/vapi/SETUP_INSTRUCTIONS.md`.

- `dvga`
  - Cloned from `dolevf/Damn-Vulnerable-GraphQL-Application` (branch `blackhatgraphql`).
  - Compose uses local `build:`; `.allow_build` is created to enable building.
  - Host port via `/opt/lab/dvga/.env` `DVGA_PORT`.

- `webgoat`
  - Healthcheck replaced with wget-based probe; default port `WEBGOAT_PORT=8080`.

- `juice-shop`
  - Runs official image `bkimminich/juice-shop`. Default port `JUICESHOP_PORT=3000`.

- `bwapp`
  - Includes MySQL 5.7 database service with persistent storage.
  - Database auto-configured with proper credentials.
  - Default port `BWAPP_PORT=8082`.

- `vampi`
  - Includes database initialization service for auto-population.
  - Prevents duplicate service conflicts in docker-compose.
  - Default port `VAMPI_PORT=8086`.

- `pixi`
  - Multiple port mappings: app (18000), admin (18090), MongoDB (27018), MongoDB HTTP (28018).
  - MongoDB ports restricted to loopback for security.
  - Default ports via `PIXI_APP_PORT`, `PIXI_ADMIN_PORT`, `PIXI_MONGO_PORT`, `PIXI_MONGO_HTTP_PORT`.

- `security-shepherd`
  - Requires Maven build to generate target/ directory files before Docker build.
  - Script automatically runs `mvn clean compile` during installation.
  - Removes obsolete `version` attribute from docker-compose.yml.
  - Default port `SECURITY_SHEPHERD_PORT=8083`.

- `lab-dashboard`
  - Web dashboard with categorized service links and GitHub integration.
  - Includes external links (GitHub, Website, Docker Hub) for each service.
  - Default port `DASHBOARD_PORT=80`.

## Healthchecks

- Replaced brittle shell features (`/dev/tcp`, missing `curl`) with `wget` or BusyBox fallback.
- Overrides are generated as `docker-compose.override.yml` where needed (e.g., crAPI, WebGoat).

## Build policy and local images

- Some services define `build:` in compose.
- The script only allows Compose to build when `.allow_build` exists under the service directory.
- This prevents accidental long builds unless explicitly required or auto-detected.

## Ports and exposure

- Default host bindings are 127.0.0.1 for safety. Use `--expose` to bind to all interfaces.
- Ports are configurable per-service via each `.env` file.

## Troubleshooting

- __Image pull denied / No such image__
  - Cause: Service expects local build or image name changed upstream.
  - Fix: Ensure `.allow_build` exists and rerun `update`/`start`, or manually run `docker compose build` in `/opt/lab/<service>/`.

- __crAPI healthcheck failing__
  - Fix: Run `update crapi` to regenerate override; script auto-detects the gateway service and writes a wget-based healthcheck.

- __WebGoat healthcheck failing (curl missing)__
  - Fix: The script now adds a wget-based check via override. Run `update webgoat` then `start webgoat`.

- __Security Shepherd build failing (target/ files not found)__
  - Cause: Security Shepherd requires Maven build to generate target/ directory files before Docker build.
  - Fix: The script automatically installs Maven and runs `mvn clean compile`. If issues persist, run `update security-shepherd` to retry the build.

- __Security Shepherd docker-compose version warning__
  - Fix: The script automatically removes the obsolete `version` attribute from docker-compose.yml.

- __YAML parse/port conflicts__
  - Fix: Ports normalized and parameterized; adjust port in the service `.env` and restart.

## Security posture and safe use

- These applications are intentionally vulnerable. Keep them off the public internet.
- Defaults favor safety:
  - Loopback bindings by default, explicit `--expose` to open.
  - No inline secrets in compose; per-service `.env` files are used.
  - Supply-chain TOFU pinning for composes and git sources.

## Observability and logging

- Script logs are UTC-timestamped and structured for easy scraping.
- Avoid logging sensitive secrets; rotate `.env` values as needed.

## Updating and pinning

- First-time use pins upstream compose by checksum and git repos by commit.
- `ALLOW_COMPOSE_CHANGE=true` allows compose updates during `update` and re-pins.

## Uninstalling a service

```bash
sudo ./manage_vuln_services.sh uninstall <service>
```

- Prompts for confirmation; use `--force` to skip.
- Removes containers, images for the project, volumes, networks, and the entire directory `/opt/lab/<service>`.

## Uninstalling installed tooling

To remove tools installed by `apisec_tool_install.sh`:

```bash
sudo ./apisec_tool_install.sh uninstall       # prompts for confirmation
sudo ./apisec_tool_install.sh uninstall --force  # non-interactive
sudo ./apisec_tool_install.sh uninstall --force --purge  # also wipes Docker data (/var/lib/docker) and removes Docker repo entry
```

## Contributing

- Issues and PRs welcome. Keep files under ~750 lines, prefer secure defaults, and avoid hard-coded secrets.
- Document major changes and update this README accordingly.

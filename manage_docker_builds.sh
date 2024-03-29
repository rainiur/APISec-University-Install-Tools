#!/bin/bash

# Define services and their setup information
declare -A services=(
    ["juice-shop"]="setup_juice_shop"
    ["crapi"]="https://raw.githubusercontent.com/OWASP/crAPI/main/deploy/docker/docker-compose.yml"
    ['dvga']="setup_dvga"
    ["vapi"]="https://github.com/roottusk/vapi.git"
)

base_dir="/opt/lab"

function is_service_installed() {
    local service=$1
    local service_dir="$base_dir/$service/docker-compose.yml"
    if [[ -f "$service_dir" ]]; then
        return 0 # true
    else
        return 1 # false
    fi
}

function ensure_dir() {
    local dir=$1
    if [ ! -d "$dir" ]; then
        echo "Creating $dir directory..."
        mkdir -p "$dir"
    else
        echo "$dir already exists."
    fi
}

function query_external_access() {
    while true; do
        echo "\n\nDo you want to make the API accessible externally from the server? (y/n)"
        read -r external_access

        case $external_access in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer y or n.";;
        esac
    done
}

function setup_juice_shop() {
    echo "Setting up Juice Shop..."
    local service_dir="$base_dir/juice-shop"
    ensure_dir "$service_dir"
    cat <<EOF >"$service_dir/docker-compose.yml"
services:
  juice-shop:
    image: bkimminich/juice-shop
    ports:
      - "3000:3000"
    restart: unless-stopped
EOF
}

function setup_dvga() {
    local service_dir="$base_dir/dvga"
    if [ ! -d "$service_dir" ]; then
        git clone -b blackhatgraphql https://github.com/dolevf/Damn-Vulnerable-GraphQL-Application.git "$service_dir"
        sed -i 's/\/opt\/dvga/\/opt\/lab\/dvga/g' "$service_dir/Dockerfile"
        cat <<EOF >"$service_dir/docker-compose.yml"
services:
  dvga:
    build:
      context: $service_dir
      dockerfile: Dockerfile
    image: dvga
    container_name: dvga
    ports:
      - "5013:5013"
    environment:
      - WEB_HOST=127.0.0.1
    restart: unless-stopped
EOF
    fi
}

function setup_docker_compose() {
    local service=$1
    local service_dir="$base_dir/$service"
    local compose_file=${services[$service]}

    ensure_dir "$service_dir"
    if is_service_installed "$service"; then
        echo "$service is already installed, performing update..."
        if [[ $compose_file == *.git ]]; then
            (cd "$service_dir" && git pull)
        else
            echo "Updating docker-compose.yml for $service"
            if [[ $compose_file != http* ]]; then
                cat >"$service_dir/docker-compose.yml" <<EOF
$compose_file
EOF
            else
                curl -o "$service_dir/docker-compose.yml" "$compose_file"
            fi
        fi
    else
        if [[ $compose_file == http* && $compose_file != *.git ]]; then
            echo "Downloading docker-compose.yml for $service"
            curl -o "$service_dir/docker-compose.yml" "$compose_file"
        elif [[ $compose_file == *.git ]]; then
            echo "Cloning $compose_file into $service_dir"
            git clone "$compose_file" "$service_dir"
        elif [[ $compose_file == "setup_"* ]]; then
            echo "Setting up $service..."
            $compose_info
        else
            echo "Writing docker-compose.yml for $service"
            cat >"$service_dir/docker-compose.yml" <<EOF
$compose_file
EOF
        fi
        if [[ $service == "crapi" || $service == 'dvga' ]]; then
            if query_external_access; then
                sudo sed -i 's/127.0.0.1/0.0.0.0/g' $service_dir/docker-compose.yml
            fi
        fi
    fi
    # After setup, pull images and start services
    echo "Pulling images and starting service for $service..."
    (cd "$service_dir" && sudo docker-compose pull && sudo docker-compose up -d)
}

function manage_service() {
    local service=$1
    local action=$2 # install, start, stop, clean
    local service_dir="$base_dir/$service"

#    if [[ $service == "dvga" ]]; then
#        if [[ $action == "install" || $action == "update" ]]; then
#            setup_dvga
#            if [[ $service == "crapi" || $service == 'dvga' ]]; then
#                if query_external_access; then
#                    sudo sed -i 's/127.0.0.1/0.0.0.0/g' $service_dir/docker-compose.yml
#                fi
#            fi
#            (cd "$service_dir" && sudo docker-compose pull && sudo docker-compose up -d)
#            return
#        fi
#    fi

    if [[ $action != "install" && $action != "update" ]] && ! is_service_installed "$service"; then
        echo "Service $service is not installed."
        return
    fi

    case $action in
        install|update)
            setup_docker_compose "$service"
            ;;
        start)
            echo "$action service: $service"
            (cd "$base_dir/$service" && sudo docker-compose up -d)
            ;;
        stop)
            echo "Stopping service: $service"
            (cd "$base_dir/$service" && sudo docker-compose down)
            ;;
        clean)
            if is_service_installed $service; then
                echo "Cleaning service: $service"
                (cd "$base_dir/$service" && sudo docker-compose down --rmi all -v)
                sudo rm -rf "$base_dir/$service"
            else
                echo "Service $service is not installed, so it cannot be cleaned."
            fi
            ;;
    esac
}

function manage_all_services() {
    local action=$1
    for service in "${!services[@]}"; do
        manage_service "$service" "$action"
    done
}

function main() {
    local action=$1
    local target=${2:-all}

    case $action in
        install|update|start|stop|clean)
            if [ "$target" == "all" ]; then
                manage_all_services "$action"
            elif [[ -v services[$target] ]]; then
                manage_service "$target" "$action"
            else
                echo "Unknown service: $target"
                exit 1
            fi
            ;;
        *)
            echo "Usage: $0 {install|update|start|stop|clean} [service_name|all]"
            exit 1
            ;;
    esac
}

# Check if the script is run as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

main "$1" "$2"

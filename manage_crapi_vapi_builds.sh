#!/bin/bash

function install_apis() {
    # Check if /opt/lab exists, create if not
    if [ ! -d "/opt/lab" ]; then
        echo "Creating /opt/lab directory..."
        mkdir -p /opt/lab
    else
        echo "/opt/lab already exists."
    fi

    # Navigate to /opt/lab before continuing with the installation
    cd /opt/lab

    sudo apt-get install docker.io docker-compose

    sudo mkdir -p crapi
    sudo curl -o crapi/docker-compose.yml https://raw.githubusercontent.com/OWASP/crAPI/main/deploy/docker/docker-compose.yml

    while true; do
        echo "Do you want to make the API accessible externally from the server? (y/n)"
        read -r external_access

        case $external_access in
            [Yy]* )
                echo "Changing 127.0.0.1 to 0.0.0.0 in docker-compose.yml files..."
                sudo sed -i 's/127.0.0.1/0.0.0.0/g' crapi/docker-compose.yml
                break;;
            [Nn]* )
                echo "Keeping APIs accessible only locally."
                break;;
            * )
                echo "Please answer y or n.";;
        esac
    done

    sudo git clone https://github.com/roottusk/vapi.git

    start_apis
}

function start_apis() {
    echo "Starting APIs..."
    cd /opt/lab/crapi
    sudo docker-compose pull
    sudo docker-compose -f docker-compose.yml --compatibility up -d

    cd ../vapi
    sudo docker-compose pull
    sudo docker-compose up -d

    cd
}

function clean_apis() {
    echo "Stopping services and cleaning up..."
    cd /opt/lab/crapi
    sudo docker-compose rm -s -f -v

    cd ../vapi
    sudo docker-compose rm -s -f -v

    cd ..
    sudo docker image prune -a -f
    sudo docker volume prune -f

    rm -rf crapi
    rm -rf vapi
}

function stop_apis() {
    echo "Stopping services"
    cd /opt/lab/crapi
    sudo docker-compose stop

    cd ../vapi
    sudo docker-compose stop

    cd
}

function restart_apis() {
    stop_apis
    start_apis
}

case "$1" in
    install)
        install_apis
        ;;
    start)
        start_apis
        ;;
    stop)
        stop_apis
        ;;
    restart)
        restart_apis
        ;;
    clean)
        clean_apis
        ;;
    *)
        echo "Usage: $0 {install|start|stop|restart|clean}"
        exit 1
        ;;
esac

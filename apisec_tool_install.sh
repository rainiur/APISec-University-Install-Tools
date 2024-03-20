#!/bin/bash

sudo apt update -y
pid=$!
wait $pid

sudo apt upgrade -y
pid=$!
wait $pid

sudo apt dist-upgrade -y
pid=$!
wait $pid

sudo apt autoremove -y
pid=$!
wait $pid

if [ ! -f /opt/jython-standalone-2.7.3.jar ]; then
	sudo wget https://repo1.maven.org/maven2/org/python/jython-standalone/2.7.3/jython-standalone-2.7.3.jar -O /opt/jython-standalone-2.7.3.jar
	pid=$!
	wait $pid
fi

echo "Add Foxy Proxy extension and add the following options:"
echo "Burpsuite 127.0.0.1 Port 8080"
echo "Postman 127.0.0.1 Port 5555"
echo $HOME
found=$(find "$HOME/.mozilla/" -type f -name "foxyproxy*.xpi")
echo $found
if [ -n "$found" ]; then
	sudo wget https://addons.mozilla.org/firefox/downloads/file/4212976/foxyproxy_standard-8.8.xpi 
	pid=$!
	wait $pid
	firefox foxyproxy_standard-8.8.xpi
	pid=$!
	wait $pid
fi

echo "Add jython from /opt and configure Autorize in Burpsuite Extensions"
if [ ! -f /usr/local/bin/BurpSuitePro ]; then
    burpsuite
else
    BurpSuitePro
fi
#BurpSuitePro
pid=$!
wait $pid

cd /opt

if [ ! -f /opt/Postman/Postman ]; then
	echo "Create account and log into Postman and create a new workspace"
	sudo wget https://dl.pstmn.io/download/latest/linux64 -O postman-linux-x64.tar.gz
	pid=$!
	wait $pid
	sudo tar -xvzf postman-linux-x64.tar.gz
	pid=$!
	wait $pid
	sudo ln -s /opt/Postman/Postman /usr/bin/postman
fi

sudo pip3 install mitmproxy2swagger
pid=$!
wait $pid

sudo apt install git docker-compose docker.io golang-go zaproxy -y
pid=$!
wait $pid

sudo ln -s /usr/share/zaproxy/zap.sh /usr/bin/zap
zap -cmd -addonupdate
zap -cmd -addoninstall openapi
zap
pid=$!
wait $pid

# Add hapihacker user
if [ ! id "hapihacker" &>/dev/null ]; then
	sudo useradd -m hapihacker
	sudo usermod -a -G sudo hapihacker
	sudo chsh -s /bin/zsh hapihacker
	echo "Create password for hapihacker user"
	sudo passwd hapihacker
fi

cd /opt
if [ ! -f /opt/jwt_tool/jwt_tool.py ]; then
	sudo git clone https://github.com/ticarpi/jwt_tool
	pid=$!
	wait $pid
	cd jwt_tool
	sudo python3 -m pip install termcolor cprint pycryptodomex requests
	pid=$!
	wait $pid
	sudo chmod +x jwt_tool.py
	sudo ln -s /opt/jwt_tool/jwt_tool.py /usr/bin/jwt_tool
fi

if [ ! -f /opt/kiterunner/dist/kr ]; then
	cd /opt
	sudo git clone https://github.com/assetnote/kiterunner.git
	cd kiterunner
	sudo make build
	sudo ln -s /opt/kiterunner/dist/kr /usr/bin/kr
fi

if [ ! -f /opt/Arjun/setup.py ]; then
	cd /opt
	sudo git clone https://github.com/s0md3v/Arjun.git
	cd Arjun
	sudo python3 setup.py install
fi

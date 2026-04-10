#!/usr/bin/env bash

# Built-in setup for bWAPP.
# Expects BASE_DIR, ensure_dir, and write_env_port from the main script.
setup_bwapp_impl() {
  local dir="$BASE_DIR/bwapp"
  ensure_dir "$dir"
  write_env_port "$dir" BWAPP_PORT 8082

  # Create Dockerfile that extends hackersploit/bwapp-docker
  cat >"$dir/Dockerfile" <<'EOF'
FROM hackersploit/bwapp-docker

# Create startup script
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Override the default command
CMD ["/start.sh"]
EOF

  # Also patch /start-apache2.sh in the Dockerfile to clear stale PID file
  cat >>"$dir/Dockerfile" <<'DEOF'

# Patch upstream start-apache2.sh to remove stale PID before launching
RUN sed -i '2i rm -f /var/run/apache2/apache2.pid' /start-apache2.sh
DEOF

  # Create startup script
  cat >"$dir/start.sh" <<'EOF'
#!/bin/bash

# Start the original bWAPP services
echo "Starting bWAPP services..."
/run.sh &

# Wait for services to be ready
echo "Waiting for services to be ready..."
sleep 60

# Try to install bWAPP database schema multiple times
echo "Installing bWAPP database schema..."
INSTALL_SUCCESS=false
for i in {1..5}; do
    echo "Attempt $i/5..."
    if curl -s "http://localhost/install.php?install=yes" >/dev/null 2>&1; then
        echo "Database installation successful!"
        INSTALL_SUCCESS=true
        break
    else
        echo "Database installation failed, retrying in 10 seconds..."
        sleep 10
    fi
done

# If automatic installation failed, use manual fallback
if [ "$INSTALL_SUCCESS" = false ]; then
    echo "Automatic installation failed, using manual fallback..."

    # Wait for MySQL to be fully ready
    echo "Waiting for MySQL to be ready..."
    sleep 30

    # Create database if it doesn't exist
    echo "Creating bWAPP database..."
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS bWAPP;" 2>/dev/null || echo "Database creation may have failed"

    # Create tables manually
    echo "Creating database tables..."
    mysql -u root -e "
    USE bWAPP;
    CREATE TABLE IF NOT EXISTS users (id int(10) NOT NULL AUTO_INCREMENT,login varchar(100) DEFAULT NULL,password varchar(100) DEFAULT NULL,email varchar(100) DEFAULT NULL,secret varchar(100) DEFAULT NULL,activation_code varchar(100) DEFAULT NULL,activated tinyint(1) DEFAULT '0',reset_code varchar(100) DEFAULT NULL,admin tinyint(1) DEFAULT '0',PRIMARY KEY (id)) ENGINE=InnoDB  DEFAULT CHARSET=utf8 AUTO_INCREMENT=1;
    INSERT IGNORE INTO users (login, password, email, secret, activation_code, activated, reset_code, admin) VALUES ('A.I.M.', '6885858486f31043e5839c735d99457f045affd0', 'bwapp-aim@mailinator.com', 'A.I.M. or Authentication Is Missing', NULL, 1, NULL, 1),('bee', '6885858486f31043e5839c735d99457f045affd0', 'bwapp-bee@mailinator.com', 'Any bugs?', NULL, 1, NULL, 1);
    CREATE TABLE IF NOT EXISTS blog (id int(10) NOT NULL AUTO_INCREMENT,owner varchar(100) DEFAULT NULL,entry varchar(500) DEFAULT NULL,date datetime DEFAULT NULL,PRIMARY KEY (id)) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1;
    CREATE TABLE IF NOT EXISTS visitors (id int(10) NOT NULL AUTO_INCREMENT,ip_address varchar(50) DEFAULT NULL,user_agent varchar(500) DEFAULT NULL,date datetime DEFAULT NULL,PRIMARY KEY (id)) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1;
    CREATE TABLE IF NOT EXISTS movies (id int(10) NOT NULL AUTO_INCREMENT,title varchar(100) DEFAULT NULL,release_year varchar(100) DEFAULT NULL,genre varchar(100) DEFAULT NULL,main_character varchar(100) DEFAULT NULL,imdb varchar(100) DEFAULT NULL,tickets_stock int(10) DEFAULT NULL,PRIMARY KEY (id)) ENGINE=InnoDB DEFAULT CHARSET=utf8 AUTO_INCREMENT=1;
    INSERT IGNORE INTO movies (title, release_year, genre, main_character, imdb, tickets_stock) VALUES ('G.I. Joe: Retaliation', '2013', 'action', 'Cobra Commander', 'tt1583421', 100),('Iron Man', '2008', 'action', 'Tony Stark', 'tt0371746', 53),('Man of Steel', '2013', 'action', 'Clark Kent', 'tt0770828', 78),('Terminator Salvation', '2009', 'sci-fi', 'John Connor', 'tt0438488', 100),('The Amazing Spider-Man', '2012', 'action', 'Peter Parker', 'tt0948470', 13),('The Cabin in the Woods', '2011', 'horror', 'Some zombies', 'tt1259521', 666),('The Dark Knight Rises', '2012', 'action', 'Bruce Wayne', 'tt1345836', 3);
    CREATE TABLE IF NOT EXISTS heroes (id int(10) NOT NULL AUTO_INCREMENT,login varchar(100) DEFAULT NULL,password varchar(100) DEFAULT NULL,secret varchar(100) DEFAULT NULL,PRIMARY KEY (id)) ENGINE=InnoDB  DEFAULT CHARSET=utf8 AUTO_INCREMENT=1;
    INSERT IGNORE INTO heroes (login, password, secret) VALUES ('neo', 'trinity', 'Oh why didn\'t I took that BLACK pill?'),('alice', 'loveZombies', 'There\'s a cure!'),('thor', 'Asgard', 'Oh, no... this is Earth... isn\'t it?'),('wolverine', 'Log@N', 'What\'s a Magneto?'),('johnny', 'm3ph1st0ph3l3s', 'I\'m the Ghost Rider!'),('seline', 'm00n', 'It wasn\'t the Lycans. It was you.');
    " 2>/dev/null || echo "Manual database creation may have failed"

    echo "Manual database installation completed!"
fi

# Wait a moment for database installation to complete
sleep 10

echo "bWAPP is ready! Access at http://localhost"
echo "Default credentials: bee / bug"

# Keep the original services running
wait
EOF

  # Create docker-compose.yml
  cat >"$dir/docker-compose.yml" <<'EOF'
services:
  bwapp:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "${BWAPP_PORT:-8082}:80"
    restart: unless-stopped
    volumes:
      - bwapp_data:/var/lib/mysql

volumes:
  bwapp_data:
EOF

  # Allow docker compose to build the local image
  ensure_dir "$dir"
  touch "$dir/.allow_build"
}

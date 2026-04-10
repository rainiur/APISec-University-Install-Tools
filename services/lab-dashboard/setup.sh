#!/usr/bin/env bash

# Built-in setup for lab-dashboard.
# Expects BASE_DIR, ensure_dir, and write_env_port from the main script.
setup_lab_dashboard_impl() {
  local dir="$BASE_DIR/lab-dashboard"
  ensure_dir "$dir"
  write_env_port "$dir" DASHBOARD_PORT 80

  # Create HTML dashboard
  cat >"$dir/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Security Testing Lab Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
        }

        .header {
            text-align: center;
            color: white;
            margin-bottom: 40px;
        }

        .header h1 {
            font-size: 3rem;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }

        .header p {
            font-size: 1.2rem;
            opacity: 0.9;
        }

        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }

        .card {
            background: white;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
            border-left: 5px solid #667eea;
        }

        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 15px 40px rgba(0,0,0,0.3);
        }

        .card h3 {
            color: #333;
            margin-bottom: 10px;
            font-size: 1.4rem;
        }

        .card p {
            color: #666;
            margin-bottom: 15px;
            line-height: 1.6;
        }

        .card .port {
            background: #f8f9fa;
            padding: 5px 10px;
            border-radius: 20px;
            font-size: 0.9rem;
            color: #495057;
            display: inline-block;
            margin-bottom: 15px;
        }

        .card .access-btn {
            display: inline-block;
            background: linear-gradient(45deg, #667eea, #764ba2);
            color: white;
            padding: 12px 25px;
            text-decoration: none;
            border-radius: 25px;
            font-weight: bold;
            transition: all 0.3s ease;
            box-shadow: 0 4px 15px rgba(102, 126, 234, 0.4);
        }

        .card .access-btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(102, 126, 234, 0.6);
        }

        .card .external-link {
            color: #0366d6;
            text-decoration: underline;
            margin-top: 10px;
            display: inline-block;
        }

        .card .external-link:hover {
            text-decoration: none;
        }

        .status {
            text-align: center;
            margin-top: 30px;
            color: white;
            font-size: 1.1rem;
        }

        .footer {
            text-align: center;
            color: white;
            margin-top: 40px;
            opacity: 0.8;
        }

        .category {
            margin-bottom: 30px;
        }

        .category h2 {
            color: white;
            margin-bottom: 20px;
            font-size: 1.8rem;
            text-shadow: 1px 1px 2px rgba(0,0,0,0.3);
        }
    </style>
    <script>
        document.addEventListener('DOMContentLoaded', function() {
            const host = window.location.hostname;
            document.querySelectorAll('a[data-port]').forEach(function(link) {
                const scheme = link.dataset.scheme || 'http';
                const port = link.dataset.port;
                const path = link.dataset.path || '';
                link.href = scheme + '://' + host + ':' + port + path;
            });
        });
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Security Testing Lab Dashboard</h1>
            <p>Vulnerable Applications for Comprehensive Security Testing & Learning</p>
        </div>

        <div class="category">
            <h2>API Security Testing</h2>
            <div class="grid">
                <div class="card">
                    <h3>crAPI</h3>
                    <div class="port">Port: 8888/8444</div>
                    <p>Completely Ridiculous API - A vulnerable API designed for learning API security concepts including authentication, authorization, and data validation vulnerabilities.</p>
                    <a href="#" target="_blank" class="access-btn" data-scheme="http" data-port="8888">Access crAPI</a>
                    <br><a href="https://github.com/OWASP/crAPI" target="_blank" class="external-link">GitHub</a>
                </div>

                 <div class="card">
                     <h3>VAmPI</h3>
                     <div class="port">Port: 8086</div>
                     <p>Vulnerable API - A deliberately vulnerable API built with Flask to demonstrate common API security issues and attack vectors.</p>
                     <a href="#" target="_blank" class="access-btn" data-scheme="http" data-port="8086" data-path="/ui/">Access VAmPI Swagger UI</a>
                     <br><a href="https://github.com/erev0s/VAmPI" target="_blank" class="external-link">GitHub</a>
                 </div>

                <div class="card">
                    <h3>VAPI</h3>
                    <div class="port">Port: 8000</div>
                    <p>Vulnerable API - A Laravel-based vulnerable API designed for testing various security vulnerabilities in web APIs.</p>
                    <a href="#" target="_blank" class="access-btn" data-scheme="http" data-port="8000" data-path="/vapi/">Access VAPI</a>
                    <br><a href="https://github.com/roottusk/vapi" target="_blank" class="external-link">GitHub</a>
                </div>

                <div class="card">
                    <h3>DVGA</h3>
                    <div class="port">Port: 5013</div>
                    <p>Damn Vulnerable GraphQL Application - A vulnerable GraphQL API designed for learning GraphQL security testing.</p>
                    <a href="#" target="_blank" class="access-btn" data-scheme="http" data-port="5013">Access DVGA</a>
                    <br><a href="https://github.com/dolevf/Damn-Vulnerable-GraphQL-Application" target="_blank" class="external-link">GitHub</a>
                </div>
            </div>
        </div>

        <div class="category">
            <h2>Web Application Security</h2>
            <div class="grid">
                <div class="card">
                    <h3>DVWA</h3>
                    <div class="port">Port: 8081</div>
                    <p>Damn Vulnerable Web Application - A PHP/MySQL web application that is deliberately vulnerable for learning web application security.</p>
                    <a href="#" target="_blank" class="access-btn" data-scheme="http" data-port="8081">Access DVWA</a>
                    <br><a href="https://github.com/digininja/DVWA" target="_blank" class="external-link">GitHub</a>
                </div>

                <div class="card">
                    <h3>bWAPP</h3>
                    <div class="port">Port: 8082</div>
                    <p>Buggy Web Application - A PHP application with over 100 web vulnerabilities for learning and practicing web security.</p>
                    <a href="#" target="_blank" class="access-btn" data-scheme="http" data-port="8082">Access bWAPP</a>
                    <br><a href="http://www.itsecgames.com/" target="_blank" class="external-link">Website</a>
                </div>

                <div class="card">
                    <h3>XVWA</h3>
                    <div class="port">Port: 8085</div>
                    <p>Xtreme Vulnerable Web Application - A vulnerable web application designed for learning web application security testing.</p>
                    <a href="#" target="_blank" class="access-btn" data-scheme="http" data-port="8085">Access XVWA</a>
                    <br><a href="https://hub.docker.com/r/bitnetsecdave/xvwa" target="_blank" class="external-link">Docker Hub</a>
                </div>

                <div class="card">
                    <h3>Mutillidae</h3>
                    <div class="port">Port: 8088</div>
                    <p>OWASP Mutillidae - A deliberately vulnerable web application with numerous vulnerabilities for learning web security.</p>
                    <a href="#" target="_blank" class="access-btn" data-scheme="http" data-port="8088">Access Mutillidae</a>
                    <br><a href="https://github.com/OWASP/Mutillidae-II" target="_blank" class="external-link">GitHub</a>
                </div>

                <div class="card">
                    <h3>DVWS</h3>
                    <div class="port">Port: 8087</div>
                    <p>Damn Vulnerable Web Services - A vulnerable web services application for learning web service security testing.</p>
                    <a href="#" target="_blank" class="access-btn" data-scheme="http" data-port="8087">Access DVWS</a>
                    <br><a href="https://github.com/snoopysecurity/dvws" target="_blank" class="external-link">GitHub</a>
                </div>
            </div>
        </div>

        <div class="category">
            <h2>Specialized Security Testing</h2>
            <div class="grid">
                <div class="card">
                    <h3>Security Shepherd</h3>
                    <div class="port">Port: 8083/8445</div>
                    <p>OWASP Security Shepherd - A web and mobile application security training platform with various security challenges.</p>
                    <a href="#" target="_blank" class="access-btn" data-scheme="https" data-port="8445">Access Security Shepherd (HTTPS)</a>
                    <br><a href="https://github.com/OWASP/SecurityShepherd" target="_blank" class="external-link">GitHub</a>
                </div>

                <div class="card">
                    <h3>WebGoat</h3>
                    <div class="port">Port: 8080</div>
                    <p>OWASP WebGoat - A deliberately insecure web application maintained by OWASP for learning web application security.</p>
                    <a href="#" target="_blank" class="access-btn" data-scheme="http" data-port="8080">Access WebGoat</a>
                    <br><a href="https://github.com/WebGoat/WebGoat" target="_blank" class="external-link">GitHub</a>
                </div>

                <div class="card">
                    <h3>Juice Shop</h3>
                    <div class="port">Port: 3000</div>
                    <p>OWASP Juice Shop - A modern vulnerable web application written in Node.js and Angular for learning web security.</p>
                    <a href="#" target="_blank" class="access-btn" data-scheme="http" data-port="3000">Access Juice Shop</a>
                    <br><a href="https://github.com/juice-shop/juice-shop" target="_blank" class="external-link">GitHub</a>
                </div>

                <div class="card">
                    <h3>Pixi</h3>
                    <div class="port">Port: 18000</div>
                    <p>Pixi - A vulnerable application for learning various security concepts and attack techniques.</p>
                    <a href="#" target="_blank" class="access-btn" data-scheme="http" data-port="18000">Access Pixi</a>
                    <br><a href="https://github.com/DevSlop/Pixi" target="_blank" class="external-link">GitHub</a>
                </div>
            </div>
        </div>

        <div class="status">
            <p>All services are running and ready for security testing!</p>
        </div>

        <div class="footer">
            <p>Security Testing University Lab Environment</p>
            <p>Use these applications responsibly for educational purposes only</p>
        </div>
    </div>
</body>
</html>
EOF

  cat >"$dir/docker-compose.yml" <<'EOF'
services:
  dashboard:
    image: nginx:alpine
    ports:
      - "${DASHBOARD_PORT:-80}:80"
    volumes:
      - ./index.html:/usr/share/nginx/html/index.html:ro
    restart: unless-stopped
EOF
}

#!/bin/bash
set -xe

sudo yum update -y
sudo yum install -y python3 python3-pip libcap

sudo pip3 install --upgrade pip
sudo pip3 install flask

# Allow non-root python3 to bind to port 80
sudo setcap 'cap_net_bind_service=+ep' /usr/bin/python3 || true

cat <<'EOF' | sudo tee /home/ec2-user/app.py
from flask import Flask
import socket

app = Flask(__name__)

@app.route("/")
def index():
    hostname = socket.gethostname()
    return f"Hello from {hostname}"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
EOF

cat <<'EOF' | sudo tee /etc/systemd/system/flask-app.service
[Unit]
Description=Simple Flask App
After=network.target

[Service]
User=root
WorkingDirectory=/home/ec2-user
ExecStart=/usr/bin/python3 /home/ec2-user/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo chown ec2-user:ec2-user /home/ec2-user/app.py

sudo systemctl daemon-reload
sudo systemctl enable flask-app.service
sudo systemctl start flask-app.service

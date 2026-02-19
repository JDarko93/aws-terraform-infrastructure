#!/bin/bash

# Redirect all output to log file
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=== User data script started at $(date) ==="

# Update system
echo "=== Updating system ==="
apt-get update -y
apt-get upgrade -y

# Install Node.js
echo "=== Installing Node.js ==="
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

echo "Node.js version: $(node --version)"
echo "npm version: $(npm --version)"

# Install CloudWatch agent
echo "=== Installing CloudWatch agent ==="
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E ./amazon-cloudwatch-agent.deb

# Create app
echo "=== Creating application ==="
mkdir -p /var/www/app
cd /var/www/app

# Create package.json
cat > package.json << 'PKGJSON'
{
  "name": "aws-app",
  "version": "1.0.0",
  "main": "app.js",
  "dependencies": {
    "express": "^4.18.2",
    "pg": "^8.11.0"
  }
}
PKGJSON

# Create app.js
cat > app.js << 'APPJS'
const express = require('express');
const { Pool } = require('pg');
const os = require('os');

const app = express();
const port = 3000;

const pool = new Pool({
  host: process.env.DB_ENDPOINT,
  database: process.env.DB_NAME,
  user: process.env.DB_USERNAME,
  password: process.env.DB_PASSWORD,
  port: parseInt(process.env.DB_PORT) || 5432,
  connectionTimeoutMillis: 5000,
});

app.get('/health', (req, res) => {
  res.status(200).json({ 
    status: 'healthy', 
    instance: os.hostname(),
    timestamp: new Date().toISOString()
  });
});

app.get('/', async (req, res) => {
  try {
    const result = await pool.query('SELECT NOW() as current_time');
    res.json({
      message: 'AWS Infrastructure Demo',
      instance: os.hostname(),
      environment: process.env.ENVIRONMENT,
      database_time: result.rows[0].current_time,
      database_connected: true
    });
  } catch (err) {
    res.json({
      message: 'AWS Infrastructure Demo',
      instance: os.hostname(),
      environment: process.env.ENVIRONMENT,
      database_connected: false,
      error: err.message
    });
  }
});

app.listen(port, '0.0.0.0', () => {
  console.log('=== APP STARTED ===');
  console.log('Port: ' + port);
  console.log('Environment: ' + process.env.ENVIRONMENT);
});
APPJS

# Install packages
echo "=== Installing npm packages ==="
npm install

# Create systemd service
echo "=== Creating systemd service ==="
cat > /etc/systemd/system/app.service << SVCEOF
[Unit]
Description=Node.js App
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/app
Environment="ENVIRONMENT=${environment}"
Environment="DB_ENDPOINT=${db_endpoint}"
Environment="DB_NAME=${db_name}"
Environment="DB_USERNAME=${db_username}"
Environment="DB_PASSWORD=${db_password}"
Environment="DB_PORT=${db_port}"
ExecStart=/usr/bin/node app.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SVCEOF

# Start service
echo "=== Starting app service ==="
systemctl daemon-reload
systemctl enable app.service
systemctl start app.service

sleep 10

# Check status
echo "=== App service status ==="
systemctl status app.service --no-pager

# Test locally
echo "=== Testing health endpoint ==="
curl -s http://localhost:3000/health || echo "Health check FAILED"

echo "=== User data script completed at $(date) ==="

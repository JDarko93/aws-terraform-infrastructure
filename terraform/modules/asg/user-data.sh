cat > terraform/modules/asg/user-data.sh << 'USERDATA'
#!/bin/bash

# Log everything to a file for debugging
exec > /var/log/user-data.log 2>&1
echo "Starting user data script at $(date)"

# Update system
apt-get update -y
apt-get upgrade -y

# Install Node.js 18.x
echo "Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs
node --version
npm --version

# Install CloudWatch agent
echo "Installing CloudWatch agent..."
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E ./amazon-cloudwatch-agent.deb

# Create application directory
echo "Creating application..."
mkdir -p /var/www/app
cd /var/www/app

# Create package.json
cat > /var/www/app/package.json << 'EOF'
{
  "name": "aws-app",
  "version": "1.0.0",
  "description": "AWS Infrastructure Demo App",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "pg": "^8.11.0"
  }
}
EOF

# Create application file
cat > /var/www/app/app.js << 'EOF'
const express = require('express');
const { Pool } = require('pg');
const os = require('os');

const app = express();
const port = 3000;

// Database connection
const pool = new Pool({
  host: process.env.DB_ENDPOINT,
  database: process.env.DB_NAME,
  user: process.env.DB_USERNAME,
  password: process.env.DB_PASSWORD,
  port: process.env.DB_PORT || 5432,
  connectionTimeoutMillis: 5000,
});

// Health check - does NOT require database
app.get('/health', (req, res) => {
  res.status(200).json({ 
    status: 'healthy', 
    instance: os.hostname(),
    timestamp: new Date().toISOString()
  });
});

// Root endpoint
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
    console.error('Database error:', err.message);
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
  console.log('App running on port ' + port);
  console.log('Environment: ' + process.env.ENVIRONMENT);
});
EOF

# Install dependencies
echo "Installing npm packages..."
cd /var/www/app
npm install
echo "npm install completed"

# Create systemd service
echo "Creating systemd service..."
cat > /etc/systemd/system/app.service << EOF
[Unit]
Description=Node.js App
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/app
Environment=ENVIRONMENT=${environment}
Environment=DB_ENDPOINT=${db_endpoint}
Environment=DB_NAME=${db_name}
Environment=DB_USERNAME=${db_username}
Environment=DB_PASSWORD=${db_password}
Environment=DB_PORT=${port}
ExecStart=/usr/bin/node app.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Start and enable service
echo "Starting app service..."
systemctl daemon-reload
systemctl enable app.service
systemctl start app.service

# Wait and verify app started
sleep 10
systemctl status app.service

# Test health endpoint locally
echo "Testing health endpoint..."
curl -s http://localhost:3000/health && echo "Health check passed!" || echo "Health check failed!"

# Configure CloudWatch agent
echo "Configuring CloudWatch agent..."
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json << EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "/aws/ec2/${environment}/user-data",
            "log_stream_name": "{instance_id}-user-data"
          },
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "/aws/ec2/${environment}/syslog",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

echo "User data script completed successfully at $(date)"
USERDATA
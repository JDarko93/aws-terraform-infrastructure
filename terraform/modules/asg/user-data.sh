cat > terraform/modules/asg/user-data.sh << 'EOF'
#!/bin/bash
set -e

# Update system
apt-get update -y
apt-get upgrade -y

# Install Node.js 18.x
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E ./amazon-cloudwatch-agent.deb

# Create application directory
mkdir -p /var/www/app
cd /var/www/app

# Create package.json
cat > package.json << 'PKGJSON'
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
PKGJSON

# Create application file
cat > app.js << 'APPJS'
const express = require('express');
const { Pool } = require('pg');
const os = require('os');

const app = express();
const port = 80;

// Database connection
const pool = new Pool({
  host: process.env.DB_ENDPOINT,
  database: process.env.DB_NAME,
  user: process.env.DB_USERNAME,
  password: process.env.DB_PASSWORD,
  port: 5432,
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', instance: os.hostname() });
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
    console.error('Database error:', err);
    res.json({
      message: 'AWS Infrastructure Demo',
      instance: os.hostname(),
      environment: process.env.ENVIRONMENT,
      database_connected: false,
      error: err.message
    });
  }
});

// Test database connection on startup
pool.query('SELECT 1')
  .then(() => console.log('Database connected successfully'))
  .catch(err => console.error('Database connection error:', err));

app.listen(port, '0.0.0.0', () => {
  console.log(`App running on port $${port}`);
  console.log(`Environment: $${process.env.ENVIRONMENT}`);
});
APPJS

# Set environment variables
export ENVIRONMENT=${environment}
export DB_ENDPOINT=${db_endpoint}
export DB_NAME=${db_name}
export DB_USERNAME=${db_username}
export DB_PASSWORD=${db_password}

# Install dependencies
npm install

# Create systemd service
cat > /etc/systemd/system/app.service << SYSTEMD
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
ExecStart=/usr/bin/node app.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SYSTEMD

# Start and enable service
systemctl daemon-reload
systemctl enable app.service
systemctl start app.service

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json << CWCONFIG
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "/aws/ec2/${environment}/syslog",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "${environment}/EC2",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          {"name": "cpu_usage_idle", "rename": "CPU_IDLE", "unit": "Percent"},
          "cpu_usage_iowait"
        ],
        "metrics_collection_interval": 60,
        "totalcpu": false
      },
      "disk": {
        "measurement": [
          {"name": "used_percent", "rename": "DISK_USED", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      },
      "mem": {
        "measurement": [
          {"name": "mem_used_percent", "rename": "MEM_USED", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60
      }
    }
  }
}
CWCONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

echo "User data script completed successfully"
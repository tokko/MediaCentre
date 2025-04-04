#!/bin/bash

# Wait for AdGuard to start
echo "Waiting for AdGuard to be ready..."
until curl -s -I http://localhost:3000/install.html | grep "200 OK" > /dev/null; do
  sleep 1
done

# Configure AdGuard via API with explicit fields
echo "Configuring AdGuard..."
curl -v -X POST http://localhost:3000/control/install/configure \
  -H "Content-Type: application/json" \
  -d '{
    "web": {
      "ip": "0.0.0.0",
      "port": 3000
    },
    "dns": {
      "ip": "0.0.0.0",
      "port": 53,
      "upstream_dns": ["8.8.8.8", "8.8.4.4"],
      "bootstrap_dns": ["8.8.8.8", "8.8.4.4"]
    },
    "auth": {
      "username": "admin",
      "password": "mypassword"
    }
  }' || {
  echo "API setup failed"
  exit 1
}

echo "AdGuard setup complete!"

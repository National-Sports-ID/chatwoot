#!/bin/bash
set -e

# Reload and restart Chatwoot
systemctl daemon-reload
systemctl restart chatwoot.target

# Wait and verify
sleep 10
curl -sf http://localhost:3000/auth/sign_in > /dev/null
echo "Application started successfully"

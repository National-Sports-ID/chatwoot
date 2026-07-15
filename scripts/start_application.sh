#!/bin/bash
set -e

# Reload and restart Chatwoot
systemctl daemon-reload
systemctl restart chatwoot.target

# Wait longer for the app to start fully.
sleep 20

# Check if services are running (don't fail on curl)
systemctl is-active chatwoot-web.1.service
systemctl is-active chatwoot-worker.1.service

echo "Application started successfully"

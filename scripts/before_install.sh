#!/bin/bash
set -e

# Stop chatwoot before deploying
systemctl stop chatwoot.target || true

# Backup current .env
cp /home/chatwoot/chatwoot/.env /home/chatwoot/.env.backup || true

echo "Before install complete"

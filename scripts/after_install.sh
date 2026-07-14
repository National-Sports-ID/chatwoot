#!/bin/bash
set -e

# Set correct ownership
chown -R chatwoot:chatwoot /home/chatwoot/chatwoot

# Restore .env (pipeline should never overwrite .env)
cp /home/chatwoot/.env.backup /home/chatwoot/chatwoot/.env

# Switch to chatwoot user and run setup
sudo -u chatwoot bash << 'EOF'
source /usr/local/rvm/scripts/rvm
rvm use 3.4.4
cd /home/chatwoot/chatwoot

# Install Ruby dependencies
bundle install --without development test

# Install JS dependencies
pnpm install

# Precompile assets
RAILS_ENV=production bundle exec rake assets:precompile

# Run DB migrations
RAILS_ENV=production bundle exec rake db:migrate

EOF

echo "After install complete"

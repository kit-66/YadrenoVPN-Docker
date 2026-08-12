#!/usr/bin/env bash
set -e

# entrypoint.sh — creates config.py from example if BOT_TOKEN is provided
# or expects /app/config.py to be mounted by the user.

# If user provided a config.py via bind-mount, use it.
if [ -f /app/config.py ]; then
  echo "Using provided /app/config.py"
else
  # If BOT_TOKEN provided, create config.py from example
  if [ -n "${BOT_TOKEN:-}" ]; then
    echo "Generating config.py from config.py.example"
    cp /app/config.py.example /app/config.py

    # Replace token placeholder
    sed -i "s|ВАШ_ТОКЕН_БОТА|${BOT_TOKEN}|g" /app/config.py

    # ADMIN_IDS — either a single id or comma-separated list (e.g. 123456,234567)
    if [ -n "${ADMIN_IDS:-}" ]; then
      # Remove spaces
      admin_clean=$(echo "${ADMIN_IDS}" | tr -d ' ')
      # If single numeric value, replace directly
      if [[ "$admin_clean" =~ ^[0-9]+$ ]]; then
        sed -i "s|12345678|${admin_clean}|g" /app/config.py
      else
        # Build Python list from CSV
        admin_py="ADMIN_IDS = ["
        IFS=',' read -ra arr <<< "$admin_clean"
        for i in "${arr[@]}"; do
          admin_py+="$i, "
        done
        admin_py="${admin_py%, }]"
        # Replace existing ADMIN_IDS block
        sed -i '/^ADMIN_IDS = \[/, /\]/c\'"$admin_py"" /app/config.py
      fi
    fi

    echo "config.py created"
  else
    echo "No /app/config.py and BOT_TOKEN not provided. Please mount config.py or set BOT_TOKEN env."
    exit 1
  fi
fi

# Ensure directories exist and are writable
mkdir -p /app/database /app/logs

# Execute the provided command (default: python main.py)
exec "$@"

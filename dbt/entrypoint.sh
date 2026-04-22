#!/bin/bash
set -e

# dbt entrypoint script
# Supports running dbt commands in container

echo "===================="
echo "dbt Container Started"
echo "===================="
echo "DBT_TARGET: ${DBT_TARGET:-not set}"
echo "DBT_PROFILES_DIR: ${DBT_PROFILES_DIR}"
echo "===================="

# Install dependencies if needed
if [ ! -d "dbt_packages" ]; then
    echo "Installing dbt dependencies..."
    dbt deps
fi

# Run dbt command passed as arguments
echo "Running: dbt $@"
dbt "$@"

# Capture exit code
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "dbt command completed successfully"
else
    echo "dbt command failed with exit code $EXIT_CODE"
fi

exit $EXIT_CODE

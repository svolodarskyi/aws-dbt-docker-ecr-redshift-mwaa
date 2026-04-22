#!/bin/bash
set -e

# Airflow DAG Trigger Script for MWAA
# Usage: ./trigger-dag.sh <dag_id> <environment> [config_json]
# Example: ./trigger-dag.sh dbt_transform_daily dev
# Example with config: ./trigger-dag.sh dbt_transform_daily prod '{"full_refresh": true}'

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check arguments
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <dag_id> <environment> [config_json]"
    echo ""
    echo "Examples:"
    echo "  $0 dbt_transform_daily dev"
    echo "  $0 dbt_transform_daily prod '{\"full_refresh\": true}'"
    exit 1
fi

DAG_ID=$1
ENVIRONMENT=$2
CONFIG=${3:-"{}"}

# Validate environment
if [ "$ENVIRONMENT" != "dev" ] && [ "$ENVIRONMENT" != "prod" ]; then
    echo -e "${RED}Error: Environment must be 'dev' or 'prod'${NC}"
    exit 1
fi

# MWAA environment name
MWAA_ENV_NAME="data-platform-airflow-${ENVIRONMENT}"
AWS_REGION="us-east-1"
AWS_PROFILE="data-platform-${ENVIRONMENT}"

echo "=========================================="
echo "Triggering Airflow DAG"
echo "=========================================="
echo "DAG ID: $DAG_ID"
echo "Environment: $ENVIRONMENT"
echo "MWAA Environment: $MWAA_ENV_NAME"
echo "Configuration: $CONFIG"
echo "=========================================="
echo ""

# Get CLI token
echo -e "${YELLOW}Getting MWAA CLI token...${NC}"
TOKEN_RESPONSE=$(aws mwaa create-cli-token \
    --name "$MWAA_ENV_NAME" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error getting MWAA token:${NC}"
    echo "$TOKEN_RESPONSE"
    exit 1
fi

WEB_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.WebToken')
WEB_SERVER_URL=$(echo "$TOKEN_RESPONSE" | jq -r '.WebServerHostname')

if [ -z "$WEB_TOKEN" ] || [ "$WEB_TOKEN" == "null" ]; then
    echo -e "${RED}Error: Failed to get web token${NC}"
    echo "$TOKEN_RESPONSE"
    exit 1
fi

echo -e "${GREEN}✓ Token obtained${NC}"
echo "Web Server: $WEB_SERVER_URL"
echo ""

# Trigger DAG
echo -e "${YELLOW}Triggering DAG via Airflow API...${NC}"

API_URL="https://${WEB_SERVER_URL}/api/v1/dags/${DAG_ID}/dagRuns"

# Create request body
REQUEST_BODY=$(cat <<EOF
{
  "conf": $CONFIG,
  "note": "Triggered via script by $(whoami) at $(date)"
}
EOF
)

# Call Airflow REST API
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL" \
    -H "Authorization: Bearer $WEB_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_BODY")

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | sed '$d')

# Check response
if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ]; then
    echo -e "${GREEN}✅ DAG triggered successfully!${NC}"
    echo ""
    echo "Response:"
    echo "$BODY" | jq '.'
    echo ""

    DAG_RUN_ID=$(echo "$BODY" | jq -r '.dag_run_id // .run_id // "N/A"')
    STATE=$(echo "$BODY" | jq -r '.state // "N/A"')
    EXECUTION_DATE=$(echo "$BODY" | jq -r '.execution_date // "N/A"')

    echo "=========================================="
    echo "DAG Run Details"
    echo "=========================================="
    echo "DAG Run ID: $DAG_RUN_ID"
    echo "State: $STATE"
    echo "Execution Date: $EXECUTION_DATE"
    echo "=========================================="
    echo ""
    echo "View in Airflow UI:"
    echo "https://${WEB_SERVER_URL}/dags/${DAG_ID}/grid"
    echo ""
    echo -e "${GREEN}Done!${NC}"
else
    echo -e "${RED}❌ Error triggering DAG (HTTP $HTTP_CODE)${NC}"
    echo ""
    echo "Response:"
    echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
    exit 1
fi

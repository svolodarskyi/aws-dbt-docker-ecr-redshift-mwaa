#!/usr/bin/env python3
"""
Trigger Airflow DAG in AWS MWAA

Usage:
    python trigger_dag.py <environment> <dag_id> [config_json]

Examples:
    python trigger_dag.py dev dbt_transform_daily
    python trigger_dag.py prod dbt_transform_daily '{"full_refresh": true}'
    python trigger_dag.py dev customer_pipeline '{"date": "2024-01-01"}'
"""

import sys
import json
import boto3
import requests
from datetime import datetime


def trigger_dag(environment, dag_id, conf=None, region='us-east-1'):
    """
    Trigger Airflow DAG in MWAA environment

    Args:
        environment (str): 'dev' or 'prod'
        dag_id (str): Name of the DAG to trigger
        conf (dict): Optional configuration dictionary
        region (str): AWS region (default: us-east-1)

    Returns:
        dict: Response from Airflow API or None on error
    """
    # Validate environment
    if environment not in ['dev', 'prod']:
        print(f"❌ Error: Environment must be 'dev' or 'prod', got: {environment}")
        return None

    # MWAA environment name
    env_name = f"data-platform-airflow-{environment}"

    print("=" * 60)
    print("Triggering Airflow DAG")
    print("=" * 60)
    print(f"DAG ID: {dag_id}")
    print(f"Environment: {environment}")
    print(f"MWAA Environment: {env_name}")
    print(f"Configuration: {json.dumps(conf or {}, indent=2)}")
    print("=" * 60)
    print()

    # Create MWAA client
    try:
        mwaa = boto3.client('mwaa', region_name=region)
    except Exception as e:
        print(f"❌ Error creating MWAA client: {e}")
        return None

    # Get CLI token
    print("🔑 Getting MWAA CLI token...")
    try:
        response = mwaa.create_cli_token(Name=env_name)
        web_server_url = response['WebServerHostname']
        token = response['WebToken']
        print(f"✓ Token obtained")
        print(f"  Web Server: {web_server_url}")
        print()
    except Exception as e:
        print(f"❌ Error getting MWAA token: {e}")
        return None

    # Trigger DAG via Airflow REST API
    print("🚀 Triggering DAG via Airflow API...")
    url = f"https://{web_server_url}/api/v1/dags/{dag_id}/dagRuns"
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }

    # Get current user info
    try:
        sts = boto3.client('sts')
        caller = sts.get_caller_identity()
        user_arn = caller.get('Arn', 'Unknown')
    except:
        user_arn = 'Unknown'

    data = {
        'conf': conf or {},
        'note': f'Triggered via Python script by {user_arn} at {datetime.now().isoformat()}'
    }

    try:
        response = requests.post(url, headers=headers, json=data, verify=True, timeout=30)
        response.raise_for_status()
        result = response.json()

        print("✅ DAG triggered successfully!")
        print()
        print("Response:")
        print(json.dumps(result, indent=2))
        print()

        # Extract key information
        dag_run_id = result.get('dag_run_id') or result.get('run_id', 'N/A')
        state = result.get('state', 'N/A')
        execution_date = result.get('execution_date', 'N/A')

        print("=" * 60)
        print("DAG Run Details")
        print("=" * 60)
        print(f"DAG Run ID: {dag_run_id}")
        print(f"State: {state}")
        print(f"Execution Date: {execution_date}")
        print("=" * 60)
        print()
        print("View in Airflow UI:")
        print(f"https://{web_server_url}/dags/{dag_id}/grid")
        print()

        return result

    except requests.exceptions.HTTPError as e:
        print(f"❌ HTTP Error triggering DAG: {e}")
        if hasattr(e, 'response') and e.response:
            print(f"Status Code: {e.response.status_code}")
            print(f"Response: {e.response.text}")
        return None
    except requests.exceptions.RequestException as e:
        print(f"❌ Error triggering DAG: {e}")
        return None
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return None


def main():
    """Main entry point"""
    if len(sys.argv) < 3:
        print("Usage: python trigger_dag.py <environment> <dag_id> [conf_json]")
        print()
        print("Examples:")
        print("  python trigger_dag.py dev dbt_transform_daily")
        print('  python trigger_dag.py prod dbt_transform_daily \'{"full_refresh": true}\'')
        print('  python trigger_dag.py dev customer_pipeline \'{"date": "2024-01-01"}\'')
        sys.exit(1)

    environment = sys.argv[1]
    dag_id = sys.argv[2]
    conf_str = sys.argv[3] if len(sys.argv) > 3 else None

    # Parse configuration JSON if provided
    conf = None
    if conf_str:
        try:
            conf = json.loads(conf_str)
        except json.JSONDecodeError as e:
            print(f"❌ Error parsing configuration JSON: {e}")
            print(f"   Input: {conf_str}")
            sys.exit(1)

    # Trigger DAG
    result = trigger_dag(environment, dag_id, conf)

    # Exit with appropriate code
    sys.exit(0 if result else 1)


if __name__ == "__main__":
    main()

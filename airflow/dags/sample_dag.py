"""
Sample Airflow DAG for testing MWAA environment

This DAG runs a simple hello world task to verify MWAA is operational.
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator

default_args = {
    'owner': 'data-engineering',
    'depends_on_past': False,
    'email': ['data-team@example.com'],
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

def print_environment_info(**context):
    """Print environment information"""
    import os
    import boto3

    print(f"Execution Date: {context['execution_date']}")
    print(f"AWS Region: {os.getenv('AWS_DEFAULT_REGION', 'Not set')}")
    print(f"Environment: {os.getenv('ENVIRONMENT', 'Not set')}")

    # Test AWS connectivity
    s3 = boto3.client('s3')
    print("AWS S3 connectivity: OK")

with DAG(
    dag_id='sample_hello_world',
    default_args=default_args,
    description='Sample DAG to test MWAA environment',
    schedule_interval='@daily',
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['sample', 'testing'],
) as dag:

    hello_task = BashOperator(
        task_id='say_hello',
        bash_command='echo "Hello from MWAA on $(date)"',
    )

    env_info_task = PythonOperator(
        task_id='print_env_info',
        python_callable=print_environment_info,
    )

    goodbye_task = BashOperator(
        task_id='say_goodbye',
        bash_command='echo "Goodbye from MWAA"',
    )

    hello_task >> env_info_task >> goodbye_task

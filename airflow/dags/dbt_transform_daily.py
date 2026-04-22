"""
dbt Transformation DAG

This DAG orchestrates daily dbt transformations using Cosmos.
It runs dbt models on ECS Fargate tasks.
"""

from datetime import datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.operators.python import PythonOperator
from cosmos import DbtTaskGroup, ProjectConfig, ProfileConfig, ExecutionConfig
from cosmos.profiles import RedshiftUserPasswordProfileMapping

# DAG configuration
DAG_ID = "dbt_transform_daily"
DBT_PROJECT_PATH = Path("/usr/app/dbt")
DBT_EXECUTABLE_PATH = "/root/.local/bin/dbt"

default_args = {
    'owner': 'data-engineering',
    'depends_on_past': False,
    'email': ['data-team@example.com'],
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

def send_success_notification(**context):
    """Send success notification"""
    print(f"dbt transformation completed successfully at {datetime.now()}")
    # Add SNS notification logic here if needed

def send_failure_notification(**context):
    """Send failure notification"""
    print(f"dbt transformation failed at {datetime.now()}")
    # Add SNS notification logic here if needed

with DAG(
    dag_id=DAG_ID,
    default_args=default_args,
    description='Daily dbt transformation pipeline',
    schedule_interval='0 2 * * *',  # 2 AM daily
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['dbt', 'transformation', 'production'],
    max_active_runs=1,
) as dag:

    # Pre-transformation tasks
    start_notification = PythonOperator(
        task_id='start_notification',
        python_callable=lambda: print("Starting dbt transformation..."),
    )

    # dbt task group using Cosmos
    dbt_tg = DbtTaskGroup(
        group_id="dbt_transformation",
        project_config=ProjectConfig(
            dbt_project_path=DBT_PROJECT_PATH,
        ),
        profile_config=ProfileConfig(
            profile_name="data_platform",
            target_name="prod",
            profile_mapping=RedshiftUserPasswordProfileMapping(
                conn_id="redshift_default",
                profile_args={
                    "schema": "analytics",
                },
            ),
        ),
        execution_config=ExecutionConfig(
            dbt_executable_path=DBT_EXECUTABLE_PATH,
        ),
        operator_args={
            "install_deps": True,  # Run dbt deps
        },
        default_args=default_args,
    )

    # Post-transformation tasks
    success_notification = PythonOperator(
        task_id='success_notification',
        python_callable=send_success_notification,
        trigger_rule='all_success',
    )

    failure_notification = PythonOperator(
        task_id='failure_notification',
        python_callable=send_failure_notification,
        trigger_rule='one_failed',
    )

    # Define task dependencies
    start_notification >> dbt_tg >> [success_notification, failure_notification]

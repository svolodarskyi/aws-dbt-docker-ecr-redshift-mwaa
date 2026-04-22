output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "raw_data_bucket_name" {
  description = "S3 bucket for raw data"
  value       = module.storage.raw_data_bucket_name
}

output "mwaa_bucket_name" {
  description = "S3 bucket for MWAA DAGs"
  value       = module.storage.mwaa_bucket_name
}

output "redshift_cluster_endpoint" {
  description = "Redshift cluster endpoint"
  value       = module.data.redshift_cluster_endpoint
  sensitive   = true
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.compute.ecs_cluster_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for dbt image"
  value       = module.compute.ecr_repository_url
}

output "mwaa_webserver_url" {
  description = "MWAA Airflow webserver URL"
  value       = module.orchestration.mwaa_webserver_url
}

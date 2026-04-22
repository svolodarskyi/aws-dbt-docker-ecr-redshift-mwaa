variable "aws_region" {
  description = "AWS region for the state backend"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name (used for bucket and table naming)"
  type        = string
  default     = "data-platform"
}

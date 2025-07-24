# ------------------------------------------------------------------
# Defines input variables for the Terraform configuration.
# ------------------------------------------------------------------

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "The name of the project, used for resource tagging and naming."
  type        = string
  default     = "neon-search"
}

variable "opensearch_master_user" {
  description = "The master username for the OpenSearch cluster."
  type        = string
  sensitive   = true
  default = "neon-search-master"
}

variable "opensearch_master_password" {
  description = "The master password for the OpenSearch cluster. Must be strong."
  type        = string
  sensitive   = true
  default = "Q!w2e3r4"
}

variable "opensearch_index_name" {
  description = "The name of the index in OpenSearch."
  type        = string
  default     = "user-profiles"
}

variable "container_port" {
  description = "The port the container listens on."
  type        = number
  default     = 80
}

# variable "ecr_image_uri" {
#   description = "The full URI of the Docker image in ECR (e.g., 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-repo:latest)."
#   type        = string
#   default     = "061785417701.dkr.ecr.us-east-1.amazonaws.com/neon-search:latest"
# }

variable "api_image_uri" {
  description = "The full URI of the FastAPI API Docker image in ECR."
  type        = string
}

variable "lambda_image_uri" {
  description = "The full URI of the Lambda Ingestion Docker image in ECR."
  type        = string
}

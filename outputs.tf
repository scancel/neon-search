# ------------------------------------------------------------------
# Defines outputs from our Terraform configuration.
# ------------------------------------------------------------------

output "api_load_balancer_dns" {
  description = "The public DNS name of the API Load Balancer."
  value       = aws_lb.api_alb.dns_name
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket created for data ingestion."
  value       = aws_s3_bucket.data_source_bucket.bucket
}

output "opensearch_domain_endpoint" {
  description = "The endpoint URL for the OpenSearch domain."
  value       = aws_opensearch_domain.search_cluster.endpoint
}

output "api_ecr_repository_url" {
  description = "The URL of the ECR repository for the API Docker image."
  value       = aws_ecr_repository.api_repo.repository_url
}

output "lambda_ecr_repository_url" {
  description = "The URL of the ECR repository for the Lambda Docker image."
  value       = aws_ecr_repository.lambda_repo.repository_url
}
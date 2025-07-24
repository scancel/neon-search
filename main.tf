# ------------------------------------------------------------------
# main.tf
#
# Defines the complete AWS infrastructure for the AI Search application.
# This includes networking, security, S3, OpenSearch, Lambda, and Fargate.
# ------------------------------------------------------------------

# --- Provider & Backend Configuration ---
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- Resource Naming & Randomization ---
resource "random_id" "suffix" {
  byte_length = 8
}

# ------------------------------------------------------------------
# NETWORKING
# Using the official AWS VPC module for a robust and standard setup.
# ------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.2"

  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  tags = {
    Project = var.project_name
  }
}

# ------------------------------------------------------------------
# SECURITY GROUPS
# Controls traffic between our services.
# ------------------------------------------------------------------

# Security group for the Application Load Balancer
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP traffic to ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow traffic from anywhere
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security group for the Fargate service
resource "aws_security_group" "fargate_sg" {
  name        = "${var.project_name}-fargate-sg"
  description = "Allow traffic from ALB to Fargate tasks"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] # Only allow traffic from the ALB
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------------------------------------------------
# DATA & SEARCH
# S3 Bucket, OpenSearch Cluster
# ------------------------------------------------------------------

# S3 Bucket for raw data files
resource "aws_s3_bucket" "data_source_bucket" {
  bucket = "${var.project_name}-data-source-${random_id.suffix.hex}"
}

# Amazon OpenSearch Service Domain
resource "aws_opensearch_domain" "search_cluster" {
  domain_name    = "${var.project_name}-search"
  engine_version = "OpenSearch_2.11"

  cluster_config {
    instance_type = "t3.small.search"
    instance_count = 2
    zone_awareness_enabled = true
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
  }

  vpc_options {
    subnet_ids         = module.vpc.private_subnets
    # In a real setup, you would create a dedicated SG for OpenSearch
    # and allow traffic from Lambda and Fargate SGs.
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true
    master_user_options {
      master_user_name     = var.opensearch_master_user
      master_user_password = var.opensearch_master_password
    }
  }

  access_policies = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = { AWS = "*" },
        Action = "es:*",
        Resource = "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${var.project_name}-search/*"
      }
    ]
  })

  encrypt_at_rest { enabled = true }
  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }
}

data "aws_caller_identity" "current" {}

# ------------------------------------------------------------------
# IAM ROLES & POLICIES
# ------------------------------------------------------------------

# Role for the Lambda function
resource "aws_iam_role" "lambda_ingestion_role" {
  name = "${var.project_name}-lambda-ingestion-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Policy allowing Lambda to access S3, OpenSearch, and write logs
resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.project_name}-lambda-policy"
  description = "Policy for data ingestion Lambda"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["s3:GetObject"],
        Effect   = "Allow",
        Resource = "${aws_s3_bucket.data_source_bucket.arn}/*"
      },
      {
        Action   = ["es:ESHttpPost", "es:ESHttpPut"],
        Effect   = "Allow",
        Resource = "${aws_opensearch_domain.search_cluster.arn}/*"
      },
      {
        Action   = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface"],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_ingestion_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_ingestion_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.project_name}-ecs-execution-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ------------------------------------------------------------------
# INGESTION COMPUTE (AWS Lambda)
# ------------------------------------------------------------------
# ECR Repository for the Lambda container image
resource "aws_ecr_repository" "lambda_repo" {
  name = "${var.project_name}-lambda-repo"
}

# Create CloudWatch Logs group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-ingestion-processor"
  retention_in_days = 14
}

resource "aws_lambda_function" "ingestion_processor" {
  function_name = "${var.project_name}-ingestion-processor"
  role          = aws_iam_role.lambda_ingestion_role.arn
  package_type  = "Image"
  image_uri     = var.lambda_image_uri # Pass the image URI as a variable
  timeout       = 300 # 5 minutes for model loading and processing

  vpc_config {
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.fargate_sg.id] # Re-use for simplicity
  }

  environment {
    variables = {
      OPENSEARCH_HOST  = aws_opensearch_domain.search_cluster.endpoint
      OPENSEARCH_INDEX = var.opensearch_index_name
    }
  }
}

# Trigger Lambda on S3 file creation
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.data_source_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.ingestion_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3ToCallLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestion_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.data_source_bucket.arn
}


# ------------------------------------------------------------------
# API COMPUTE (AWS Fargate)
# ------------------------------------------------------------------

# ECR Repository to store the FastAPI Docker image
resource "aws_ecr_repository" "api_repo" {
  name = "${var.project_name}-api-repo"
}

# ECS Cluster
resource "aws_ecs_cluster" "main_cluster" {
  name = "${var.project_name}-cluster"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "api_task" {
  family                   = "${var.project_name}-api-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024    # 1 vCPU
  memory                   = 2048    # 2 GB
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "${var.project_name}-container"
    image     = var.api_image_uri # IMPORTANT: Pass the image URI as a variable
    cpu       = 1024
    memory    = 2048
    essential = true
    portMappings = [{
      containerPort = var.container_port
      hostPort      = var.container_port
    }]
    environment = [
      { name = "OPENSEARCH_HOST", value = aws_opensearch_domain.search_cluster.endpoint },
      { name = "OPENSEARCH_USER", value = var.opensearch_master_user },
      { name = "OPENSEARCH_PASSWORD", value = var.opensearch_master_password },
      { name = "OPENSEARCH_INDEX", value = var.opensearch_index_name }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.api_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# CloudWatch Log Group for the API container
resource "aws_cloudwatch_log_group" "api_logs" {
  name = "/ecs/${var.project_name}-api"
}

# ECS Service
resource "aws_ecs_service" "api_service" {
  name            = "${var.project_name}-api-service"
  cluster         = aws_ecs_cluster.main_cluster.id
  task_definition = aws_ecs_task_definition.api_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.fargate_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api_tg.arn
    container_name   = "${var.project_name}-container"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.http]
}

# ------------------------------------------------------------------
# LOAD BALANCER
# ------------------------------------------------------------------
resource "aws_lb" "api_alb" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_target_group" "api_tg" {
  name        = "${var.project_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path = "/" # Health check endpoint on the FastAPI app
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.api_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_tg.arn
  }
}
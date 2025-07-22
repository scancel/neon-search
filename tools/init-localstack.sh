# This script runs automatically when LocalStack starts.
# It creates the necessary S3 bucket and Lambda function locally.

#!/bin/bash
echo "--- Initializing LocalStack resources ---"

# Set region and endpoint URL
REGION="us-east-1"
ENDPOINT_URL="http://localhost:4566"

# Create S3 Bucket
echo "Creating S3 bucket: neon-security-user-profiles-local"
awslocal s3api create-bucket \
    --bucket neon-security-user-profiles-local \
    --region $REGION

# Create Lambda Function
echo "Creating Lambda function: NeonSearchIngestionProcessor-local"
awslocal lambda create-function \
    --function-name NeonSearchIngestionProcessor-local \
    --runtime python3.11 \
    --handler main.handler \
    --memory-size 512 \
    --timeout 300 \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --zip-file fileb:///tmp/ingestion_lambda.zip \
    --environment "Variables={OPENSEARCH_HOST=opensearch,OPENSEARCH_INDEX=user-profiles,AWS_ENDPOINT_URL=http://localstack:4566}"

# Create S3 to Lambda Trigger
echo "Creating S3 trigger for Lambda"
awslocal lambda add-permission \
    --function-name NeonSearchIngestionProcessor-local \
    --statement-id s3-trigger \
    --action "lambda:InvokeFunction" \
    --principal s3.amazonaws.com \
    --source-arn arn:aws:s3:::neon-security-user-profiles-local

awslocal s3api put-bucket-notification-configuration \
    --bucket neon-security-user-profiles-local \
    --notification-configuration '{
        "LambdaFunctionConfigurations": [{
            "LambdaFunctionArn": "arn:aws:lambda:us-east-1:000000000000:function:NeonSearchIngestionProcessor-local",
            "Events": ["s3:ObjectCreated:*"]
        }]
    }'

echo "--- LocalStack initialization complete ---"
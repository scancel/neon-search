# This script runs automatically when LocalStack starts.
# It creates the necessary S3 bucket and Lambda function from a local container image.

#!/usr/bin/env bash
echo "--- Initializing LocalStack resources ---"

# Set region and endpoint URL
REGION="us-east-1"
LAMBDA_FUNCTION_NAME="NeonSearchIngestionProcessor-local"
S3_BUCKET_NAME="neon-security-user-profiles-local"
LAMBDA_IMAGE_NAME="neon-search-lambda-local:latest"

# Create S3 Bucket
echo "Creating S3 bucket: ${S3_BUCKET_NAME}"
awslocal s3api create-bucket \
    --bucket ${S3_BUCKET_NAME} \
    --region $REGION

# Create Lambda Function from local Docker image
echo "Creating Lambda function '${LAMBDA_FUNCTION_NAME}' from image '${LAMBDA_IMAGE_NAME}'"
awslocal lambda create-function \
    --function-name ${LAMBDA_FUNCTION_NAME} \
    --package-type Image \
    --code ImageUri=${LAMBDA_IMAGE_NAME} \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --timeout 300 \
    --memory-size 1024 \
    --environment "Variables={OPENSEARCH_HOST=opensearch,OPENSEARCH_INDEX=user-profiles,AWS_ENDPOINT_URL=http://localstack:4566}"

# Create S3 to Lambda Trigger
echo "Creating S3 trigger for Lambda"
awslocal lambda add-permission \
    --function-name ${LAMBDA_FUNCTION_NAME} \
    --statement-id s3-trigger \
    --action "lambda:InvokeFunction" \
    --principal s3.amazonaws.com \
    --source-arn arn:aws:s3:::${S3_BUCKET_NAME}

awslocal s3api put-bucket-notification-configuration \
    --bucket ${S3_BUCKET_NAME} \
    --notification-configuration '{
        "LambdaFunctionConfigurations": [{
            "LambdaFunctionArn": "arn:aws:lambda:us-east-1:000000000000:function:'${LAMBDA_FUNCTION_NAME}'",
            "Events": ["s3:ObjectCreated:*"]
        }]
    }'

echo "--- LocalStack initialization complete ---"
# This script zips the ingestion function code and dependencies
# and prepares it for deployment to LocalStack or AWS Lambda.

#!/bin/bash
echo "--- Starting to prepare Lambda function for deployment  ---"
cd ..
# Set ingestion directory path
DIR="ingestion_lambda"

# Clean up previous zip file
if [ -f ingestion_lambda.zip ]; then
    echo "Removing old ingestion_lambda.zip"
    rm ingestion_lambda.zip
fi
cd $DIR
# Create a temporary directory for packaging
mkdir -p ./packages && rm -rf ./packages/*
# Install dependencies into the packages directory
pip install -r requirements.txt -t ./packages
# Zip the packages
echo "Compressing dependencies and function code into ingestion_lambda.zip"
cd packages
zip -r ../../ingestion_lambda.zip .
cd ..
# Zip the function code
zip -g ../ingestion_lambda.zip main.py   
echo "--- Done preparing Lambda function for deployment  ---"
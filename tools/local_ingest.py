# ------------------------------------------------------------------
# A script to upload a file to the local S3 bucket, triggering the local Lambda.
# ------------------------------------------------------------------
import argparse
import os

import boto3

# --- Configuration ---
LOCALSTACK_ENDPOINT = "http://localhost:4566"
BUCKET_NAME = "neon-security-user-profiles-local"


def upload_to_local_s3(file_path):
    """Uploads a file to the LocalStack S3 bucket."""
    if not os.path.exists(file_path):
        print(f"Error: File not found at '{file_path}'")
        return

    file_name = os.path.basename(file_path)

    print(f"Connecting to LocalStack S3 at {LOCALSTACK_ENDPOINT}...")
    s3_client = boto3.client(
        "s3",
        endpoint_url=LOCALSTACK_ENDPOINT,
        aws_access_key_id="test",  # dummy credentials for local
        aws_secret_access_key="test",
        region_name="us-east-1",
    )

    try:
        print(f"Uploading '{file_name}' to bucket '{BUCKET_NAME}'...")
        with open(file_path, "rb") as f:
            s3_client.upload_fileobj(f, BUCKET_NAME, file_name)
        print("Upload successful! This should trigger the local Lambda function.")
    except Exception as e:
        print(f"An error occurred during upload: {e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Upload a data file to the local S3 (LocalStack) to trigger the ingestion Lambda."
    )
    parser.add_argument(
        "file", help="The path to the data file (e.g., 'data/users.csv')."
    )
    args = parser.parse_args()

    upload_to_local_s3(args.file)

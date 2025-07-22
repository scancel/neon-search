# ------------------------------------------------------------------
# AWS Lambda function for processing and indexing data from S3.
# This code would be packaged and deployed as a Lambda function.
# ------------------------------------------------------------------
import json
import logging
import os
import uuid

import boto3
import pandas as pd
from opensearchpy import OpenSearch, RequestsHttpConnection
from sentence_transformers import SentenceTransformer

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# --- Environment-aware Setup ---
OPENSEARCH_HOST = os.environ["OPENSEARCH_HOST"]
OPENSEARCH_INDEX = os.environ.get("OPENSEARCH_INDEX", "user-profiles")
AWS_ENDPOINT_URL = os.environ.get("AWS_ENDPOINT_URL")  # Will be set by LocalStack


def get_boto_client(service_name):
    """Returns a boto3 client, configured for LocalStack if applicable."""
    if AWS_ENDPOINT_URL:
        logger.info(f"Connecting to local {service_name} at {AWS_ENDPOINT_URL}")
        return boto3.client(
            service_name,
            endpoint_url=AWS_ENDPOINT_URL,
            aws_access_key_id="test",
            aws_secret_access_key="test",
            region_name="us-east-1",
        )
    else:  # Cloud environment
        return boto3.client(service_name)


def get_opensearch_client_lambda():
    """Returns an OpenSearch client for the Lambda environment."""
    if AWS_ENDPOINT_URL:  # LocalStack
        return OpenSearch(
            hosts=[{"host": OPENSEARCH_HOST, "port": 9200}],
            http_auth=None,
            use_ssl=False,
            verify_certs=False,
            connection_class=RequestsHttpConnection,
        )
    else:  # Cloud (IAM auth)
        from opensearchpy import AWSV4SignerAuth

        credentials = boto3.Session().get_credentials()
        auth = AWSV4SignerAuth(credentials, os.environ["AWS_REGION"], "es")
        return OpenSearch(
            hosts=[{"host": OPENSEARCH_HOST, "port": 443}],
            http_auth=auth,
            use_ssl=True,
            verify_certs=True,
            connection_class=RequestsHttpConnection,
        )


s3_client = get_boto_client("s3")
opensearch_client = get_opensearch_client_lambda()

# Models are loaded from a Lambda Layer or included in the deployment package
embedding_model = SentenceTransformer("all-MiniLM-L6-v2")


def handler(event, context):
    """Main Lambda handler function."""
    logger.info(f"Received event: {json.dumps(event)}")

    # Get the object from the event
    bucket = event["Records"][0]["s3"]["bucket"]["name"]
    key = event["Records"][0]["s3"]["object"]["key"]

    try:
        # Get file content from S3
        response = s3_client.get_object(Bucket=bucket, Key=key)
        file_content = response["Body"].read()

        # Parse file based on extension
        if key.endswith(".json"):
            profiles = parse_json(file_content, key)
        elif key.endswith(".csv"):
            profiles = parse_csv(file_content, key)
        elif key.endswith(".txt"):
            profiles = parse_txt(file_content, key)
        else:
            logger.warning(f"Unsupported file type for key: {key}")
            return {"status": "Unsupported file type"}

        # Index profiles into OpenSearch
        index_profiles(profiles)

        return {
            "statusCode": 200,
            "body": json.dumps(
                f"Successfully processed and indexed {len(profiles)} profiles from {key}"
            ),
        }
    except Exception as e:
        logger.error(
            f"Error processing file {key} from bucket {bucket}: {e}", exc_info=True
        )
        raise e


def parse_json(content, source_file):
    """Parses a JSON file containing a single user profile."""
    data = json.loads(content)
    profile = {
        "id": data.get("user_id", str(uuid.uuid4())),
        "name": data.get("full_name"),
        "location": data.get("location"),
        "role": data.get("job_title"),
        "skills": data.get("skills", []),
        "notes": data.get("notes"),
        "source_file": source_file,
        "raw_data": data,
    }
    return [profile]


def parse_csv(content, source_file):
    """Parses a CSV file containing multiple user profiles."""
    from io import StringIO

    df = pd.read_csv(StringIO(content.decode("utf-8")))
    profiles = []
    for _, row in df.iterrows():
        data = row.to_dict()
        profile = {
            "id": str(uuid.uuid4()),
            "name": data.get("name"),
            "location": data.get("location"),
            "role": data.get("role"),
            "skills": [
                s.strip() for s in data.get("skills", "").split(",") if s.strip()
            ],
            "notes": f"User with {data.get('experience_years')} years of experience.",
            "source_file": source_file,
            "raw_data": data,
        }
        profiles.append(profile)
    return profiles


def parse_txt(content, source_file):
    """Parses a free-form text file as notes for a single user."""
    text = content.decode("utf-8")
    # Simple parsing: assume the first two words are the name.
    # A more advanced version would use an NER model here.
    name = " ".join(text.split()[:2])
    profile = {
        "id": str(uuid.uuid4()),
        "name": name,
        "notes": text,
        "source_file": source_file,
        "raw_data": {"text": text},
    }
    return [profile]


def index_profiles(profiles):
    """Generates embeddings and indexes profiles into OpenSearch."""
    for profile in profiles:
        # Create a single text block for embedding
        text_to_embed = f"""
        Name: {profile.get("name", "")}
        Role: {profile.get("role", "")}
        Location: {profile.get("location", "")}
        Skills: {", ".join(profile.get("skills", []))}
        Notes: {profile.get("notes", "")}
        """

        # Generate embedding
        embedding = embedding_model.encode(text_to_embed.strip()).tolist()
        profile_with_embedding = {**profile, "embedding": embedding}

        # Index into OpenSearch
        opensearch_client.index(
            index=OPENSEARCH_INDEX,
            body=profile_with_embedding,
            id=profile["id"],
            refresh=True,  # For demo purposes; in prod, use batching and no refresh
        )
        logger.info(f"Indexed profile with ID: {profile['id']}")

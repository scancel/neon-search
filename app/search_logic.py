# ------------------------------------------------------------------
# Contains the core logic for performing the hybrid search with LLM analysis.
# ------------------------------------------------------------------
import json
import logging

from openai import AsyncOpenAI
from opensearchpy import OpenSearch, RequestsHttpConnection
from sentence_transformers import SentenceTransformer

from .config import settings
from .models import SearchResult

logger = logging.getLogger(__name__)
aclient = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)


# --- Initialize Clients and Models ---
def get_opensearch_client():
    """Initializes and returns an OpenSearch client based on environment."""
    if settings.OPENSEARCH_HOST == "opensearch":  # Local Docker environment
        logger.info("Connecting to local OpenSearch...")
        return OpenSearch(
            hosts=[{"host": settings.OPENSEARCH_HOST, "port": 9200}],
            http_auth=None,
            use_ssl=False,
            verify_certs=False,
            connection_class=RequestsHttpConnection,
        )
    else:  # Cloud environment
        logger.info("Connecting to cloud OpenSearch...")
        return OpenSearch(
            hosts=[{"host": settings.OPENSEARCH_HOST, "port": 443}],
            http_auth=(settings.OPENSEARCH_USER, settings.OPENSEARCH_PASSWORD),
            use_ssl=True,
            verify_certs=True,
            connection_class=RequestsHttpConnection,
        )


# --- Initialize Clients and Models ---
try:
    opensearch_client = get_opensearch_client()
    logger.info("OpenSearch client initialized.")
except Exception as e:
    logger.error(f"Failed to initialize OpenSearch client: {e}", exc_info=True)
    opensearch_client = None

try:
    embedding_model = SentenceTransformer("all-MiniLM-L6-v2")
    logger.info("SentenceTransformer model loaded.")
except Exception as e:
    logger.error(f"Failed to load SentenceTransformer model: {e}", exc_info=True)
    embedding_model = None

if settings.OPENAI_API_KEY:
    logger.info("OpenAI client configured.")


# --- LLM Query Analysis Function ---
async def get_structured_filters_from_llm(query_text: str) -> dict:
    """
    Uses an LLM to parse a natural language query into a structured JSON of filters.
    """
    if not settings.OPENAI_API_KEY:
        logger.warning(
            "OpenAI API key not found. Skipping structured filter extraction."
        )
        return {}

    # This prompt instructs the LLM to act as a search query parser.
    # It's a "zero-shot" prompt with clear instructions and a desired output format.
    system_prompt = """
    You are an expert at parsing natural language search queries into structured JSON filters.
    Your task is to extract key entities from the user's query.
    The possible filter fields are: 'role', 'location', and 'skills'.
    If a value is not present for a field, do not include the key in the JSON.
    Always respond with only a valid JSON object and nothing else.
    """

    try:
        logger.info("Requesting structured filters from LLM...")
        response = await aclient.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": f"Query: '{query_text}'"},
            ],
            temperature=0,
            max_tokens=100,
        )

        content = response.choices[0].message["content"]
        logger.info(f"LLM response: {content}")

        # Parse the JSON response from the LLM
        structured_filters = json.loads(content)
        return structured_filters
    except Exception as e:
        logger.error(
            f"Error calling OpenAI or parsing its response: {e}. Falling back to semantic search.",
            exc_info=True,
        )
        return {}  # Return empty dict on failure to gracefully fall back


# --- Main Search Function ---
async def perform_hybrid_search(query_text: str, top_k: int) -> list[SearchResult]:
    """
    Executes a hybrid keyword and semantic search against OpenSearch.
    """
    if not opensearch_client or not embedding_model:
        raise RuntimeError("Search components are not initialized.")

    # 1. Get structured filters from the LLM
    structured_filters = await get_structured_filters_from_llm(query_text)

    # 2. Generate vector embedding for the original query
    query_vector = embedding_model.encode(query_text).tolist()

    # 3. Construct the OpenSearch query
    # This is the core of the hybrid search.
    search_query = {
        "size": top_k,
        "_source": {"excludes": ["embedding"]},
        "query": {
            "hybrid": {
                "queries": [
                    {
                        "bool": {
                            "must": [{"match_all": {}}],
                            # The 'filter' clause is highly efficient. It narrows down the
                            # documents before scoring and vector search.
                            "filter": [
                                {"match": {field: value}}
                                for field, value in structured_filters.items()
                            ],
                        }
                    },
                    {"knn": {"embedding": {"vector": query_vector, "k": top_k}}},
                ]
            }
        },
    }

    # If no filters were extracted, fall back to a pure k-NN search
    if not structured_filters:
        logger.info(
            "No structured filters found, performing pure semantic k-NN search."
        )
        search_query = {
            "size": top_k,
            "_source": {"excludes": ["embedding"]},
            "query": {"knn": {"embedding": {"vector": query_vector, "k": top_k}}},
        }

    logger.info(f"Executing OpenSearch query: {json.dumps(search_query, indent=2)}")

    # 4. Execute the search
    response = opensearch_client.search(
        index=settings.OPENSEARCH_INDEX, body=search_query
    )

    # 5. Parse and format the results
    results = []
    for hit in response["hits"]["hits"]:
        score = hit["_score"]
        profile_data = hit["_source"]

        explanation = f"Matched with a relevance score of {score:.2f}."
        if structured_filters:
            explanation += f" Filtered by: {json.dumps(structured_filters)}."

        results.append(
            SearchResult(score=score, profile=profile_data, explanation=explanation)
        )

    return results

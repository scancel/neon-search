# ------------------------------------------------------------------
# app/main.py
#
# Main FastAPI application file. Defines API endpoints and startup logic.
# ------------------------------------------------------------------
import logging
import os

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse

# Add these new imports
from fastapi.staticfiles import StaticFiles

from .config import settings
from .models import SearchQuery, SearchResult
from .search_logic import perform_hybrid_search

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Neon Security AI Search API",
    description="An API for searching user profiles using natural language.",
    version="1.0.0",
)

# Define the path to the frontend directory
frontend_dir = os.path.join(os.path.dirname(__file__), "..", "frontend")

# Mount the static directory to serve files like CSS, JS, images if you add them later
app.mount("/static", StaticFiles(directory=frontend_dir), name="static")


@app.get("/", response_class=FileResponse, tags=["GUI"])
async def read_index():
    """Serves the main GUI page."""
    return os.path.join(frontend_dir, "index.html")


@app.on_event("startup")
async def startup_event():
    logger.info("API Starting Up...")
    logger.info(f"OpenSearch host: {settings.OPENSEARCH_HOST}")
    # Here you could add a check to ensure connection to OpenSearch is valid
    # and the required index exists.


@app.get("/", tags=["Health Check"])
async def read_root():
    """Health check endpoint."""
    return {"status": "API is running"}


@app.post("/search", response_model=list[SearchResult], tags=["Search"])
async def search_users(query: SearchQuery):
    """
    Performs a natural language search for user profiles.

    This endpoint takes a natural language query, uses an LLM to understand
    the intent (if available), and performs a hybrid search on the OpenSearch index.
    """
    if not query.query_text:
        raise HTTPException(status_code=400, detail="Query text cannot be empty.")

    try:
        logger.info(f"Received search query: '{query.query_text}'")
        results = await perform_hybrid_search(
            query_text=query.query_text, top_k=query.top_k
        )
        return results
    except Exception as e:
        logger.error(f"An error occurred during search: {e}", exc_info=True)
        raise HTTPException(
            status_code=500, detail="An internal error occurred during search."
        )

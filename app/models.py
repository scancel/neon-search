# ------------------------------------------------------------------
# app/models.py
#
# Pydantic models for API request/response validation and data structures.
# ------------------------------------------------------------------
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class SearchQuery(BaseModel):
    query_text: str = Field(..., description="The natural language search query.")
    top_k: int = Field(
        5, gt=0, le=50, description="The number of top results to return."
    )


class UnifiedUserProfile(BaseModel):
    """A standardized schema for user profiles from any source."""

    id: str = Field(description="A unique identifier for the user.")
    name: Optional[str] = None
    location: Optional[str] = None
    role: Optional[str] = None
    skills: List[str] = []
    notes: Optional[str] = None
    source_file: str = Field(description="The original file the data came from.")
    raw_data: Dict[str, Any] = Field(description="The original data from the source.")


class SearchResult(BaseModel):
    """Defines the structure of a single search result item."""

    score: float = Field(description="The relevance score of the match.")
    profile: UnifiedUserProfile
    explanation: str = Field(
        description="A human-readable explanation of why this result matched."
    )

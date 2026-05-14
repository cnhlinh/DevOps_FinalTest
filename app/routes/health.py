import os

from fastapi import APIRouter

from app.models import HealthResponse

router = APIRouter()

APP_VERSION = os.getenv("APP_VERSION", "0.1.0")
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")


@router.get("/health", response_model=HealthResponse, tags=["health"])
async def health_check():
    return HealthResponse(
        status="healthy",
        version=APP_VERSION,
        environment=ENVIRONMENT,
    )

from fastapi import FastAPI

from app.routes import health

app = FastAPI(
    title="DevOps Pipeline API",
    description="FastAPI application with full CI/CD pipeline",
    version="0.1.0",
)

app.include_router(health.router)

from fastapi import FastAPI

from app.routes import health, items

app = FastAPI(
    title="DevOps Pipeline API",
    description="FastAPI application with full CI/CD pipeline",
    version="0.1.0",
)

app.include_router(health.router)
app.include_router(items.router, prefix="/items", tags=["items"])


@app.get("/", tags=["root"])
async def root():
    return {"message": "DevOps Pipeline API", "version": "0.1.0"}

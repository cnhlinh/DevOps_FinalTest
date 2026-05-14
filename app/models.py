from typing import Optional

from pydantic import BaseModel, Field


class ItemCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    description: Optional[str] = Field(None, max_length=500)
    price: float = Field(..., gt=0)
    available: bool = True


class Item(ItemCreate):
    id: int


class HealthResponse(BaseModel):
    status: str
    version: str
    environment: str

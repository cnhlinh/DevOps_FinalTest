import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.routes import items as items_module


@pytest.fixture(autouse=True)
def reset_items_state():
    """Reset in-memory item store before each test for isolation."""
    from app.models import Item

    items_module._items = [
        Item(id=1, name="Widget", description="A standard widget", price=9.99),
        Item(id=2, name="Gadget", description="An advanced gadget", price=29.99),
    ]
    items_module._counter = 3
    yield


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c

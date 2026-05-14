import pytest


def test_list_items_returns_200(client):
    response = client.get("/items/")
    assert response.status_code == 200


def test_list_items_returns_list(client):
    items = client.get("/items/").json()
    assert isinstance(items, list)
    assert len(items) == 2


def test_get_existing_item(client):
    response = client.get("/items/1")
    assert response.status_code == 200
    item = response.json()
    assert item["id"] == 1
    assert item["name"] == "Widget"


def test_get_nonexistent_item_returns_404(client):
    response = client.get("/items/9999")
    assert response.status_code == 404


def test_create_item_returns_201(client):
    payload = {"name": "New Item", "price": 5.99}
    response = client.post("/items/", json=payload)
    assert response.status_code == 201


def test_create_item_response_matches_payload(client):
    payload = {"name": "Test Widget", "description": "A test", "price": 12.50, "available": True}
    data = client.post("/items/", json=payload).json()
    assert data["name"] == payload["name"]
    assert data["description"] == payload["description"]
    assert data["price"] == payload["price"]
    assert data["id"] is not None


def test_create_item_appears_in_list(client):
    client.post("/items/", json={"name": "Extra", "price": 1.00})
    items = client.get("/items/").json()
    assert len(items) == 3


@pytest.mark.parametrize(
    "payload,expected_status",
    [
        ({"name": "", "price": 5.00}, 422),
        ({"name": "X", "price": -1.00}, 422),
        ({"price": 5.00}, 422),
    ],
)
def test_create_item_validation(client, payload, expected_status):
    assert client.post("/items/", json=payload).status_code == expected_status


def test_delete_existing_item(client):
    response = client.delete("/items/1")
    assert response.status_code == 204


def test_delete_removes_item_from_list(client):
    client.delete("/items/1")
    items = client.get("/items/").json()
    assert all(i["id"] != 1 for i in items)


def test_delete_nonexistent_item_returns_404(client):
    response = client.delete("/items/9999")
    assert response.status_code == 404

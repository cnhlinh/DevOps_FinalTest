def test_health_returns_200(client):
    response = client.get("/health")
    assert response.status_code == 200


def test_health_status_is_healthy(client):
    data = client.get("/health").json()
    assert data["status"] == "healthy"


def test_health_has_version(client):
    data = client.get("/health").json()
    assert "version" in data
    assert data["version"]


def test_health_has_environment(client):
    data = client.get("/health").json()
    assert "environment" in data


def test_root_returns_200(client):
    response = client.get("/")
    assert response.status_code == 200


def test_root_has_message(client):
    data = client.get("/").json()
    assert "message" in data
    assert "version" in data

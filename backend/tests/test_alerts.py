from fastapi.testclient import TestClient

from app.alerts import city_alerts
from app.main import app
from app.services.weather import MIAMI_LAT, MIAMI_LNG, WeatherAlert, WeatherClient, WeatherReport, classify_alert


class FloodWeather:
    def __init__(self):
        self.point = None

    async def report(self, lat, lng):
        self.point = (lat, lng)
        return WeatherReport(
            "Heavy rain",
            81,
            [WeatherAlert("Flood Warning", "Flood Warning for Miami-Dade", True)],
        )


def test_city_alerts_uses_downtown_miami_and_the_flood_flag():
    weather = FloodWeather()
    result = __import__("asyncio").run(city_alerts(weather))
    assert weather.point == (MIAMI_LAT, MIAMI_LNG)
    assert result.place == "Miami"
    assert result.flood_active is True
    assert result.alerts == ["Flood Warning for Miami-Dade"]
    assert result.advisories[0].category == "flood"
    assert result.advisories[0].is_watch is False
    assert result.forecast == "Heavy rain"
    assert "not a reported road closure" in result.notice


def test_alert_categories_keep_watches_separate_from_active_flooding():
    assert classify_alert("Hurricane Watch") == ("hurricane", True)
    assert classify_alert("Tropical Storm Warning") == ("hurricane", False)
    assert classify_alert("Storm Surge Warning") == ("hurricane", False)
    assert classify_alert("Severe Thunderstorm Warning") == ("storm", False)
    assert classify_alert("Special Marine Warning") == ("storm", False)
    assert classify_alert("Flash Flood Warning") == ("heavy_rain", False)
    assert classify_alert("Heavy Rain Warning") == ("heavy_rain", False)
    assert classify_alert("Flood Warning") == ("flood", False)
    assert classify_alert("Coastal Flood Advisory") == ("flood", False)
    assert classify_alert("Flood Watch") == ("flood", True)
    assert classify_alert("Heat Advisory") == (None, False)


def test_alerts_route_uses_the_requested_point(monkeypatch):
    seen = {}

    async def report(self, lat, lng):
        seen["point"] = (lat, lng)
        return WeatherReport("Sunny", 86, [WeatherAlert("Hurricane Watch", "Hurricane Watch for South Florida", False)])

    monkeypatch.setattr(WeatherClient, "report", report)
    with TestClient(app) as client:
        response = client.get("/api/alerts", params={"lat": 25.8, "lng": -80.2})
    assert response.status_code == 200
    body = response.json()
    assert seen["point"] == (25.8, -80.2)
    assert body["place"] == "Your location"
    assert body["flood_active"] is False
    assert body["advisories"][0]["category"] == "hurricane"
    assert body["advisories"][0]["is_watch"] is True


def test_alerts_route_rejects_a_single_coordinate():
    response = TestClient(app).get("/api/alerts", params={"lat": 25.8})
    assert response.status_code == 400


def test_alerts_route_returns_503_when_the_weather_service_fails(monkeypatch):
    async def fail(self, lat, lng):
        raise RuntimeError("nws down")

    monkeypatch.setattr(WeatherClient, "report", fail)
    with TestClient(app) as client:
        response = client.get("/api/alerts")
    assert response.status_code == 503
    assert response.json()["detail"] == "weather_unavailable"

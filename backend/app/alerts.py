from app.planning import NOTICE
from app.schemas import AdvisoryOut, AlertsOut
from app.services.weather import MIAMI_LAT, MIAMI_LNG, WeatherAlert, WeatherClient, classify_alert


def advisory_from(alert: WeatherAlert) -> AdvisoryOut | None:
    category = alert.category
    is_watch = alert.is_watch
    if not category:
        category, is_watch = classify_alert(alert.event)
    if not category:
        return None
    plain = alert.instruction or alert.headline
    return AdvisoryOut(
        event=alert.event,
        headline=alert.headline,
        severity=alert.severity or None,
        urgency=alert.urgency or None,
        instruction=alert.instruction or None,
        onset=alert.onset,
        ends=alert.ends,
        category=category,
        is_watch=is_watch,
        plain_language=plain,
    )


async def alerts_for(weather: WeatherClient, lat: float, lng: float, place: str) -> AlertsOut:
    report = await weather.report(lat, lng)
    advisories = [item for item in (advisory_from(alert) for alert in report.alerts) if item is not None]
    return AlertsOut(
        place=place,
        forecast=report.forecast,
        temperature_f=report.temperature_f,
        alerts=report.headlines,
        flood_active=report.flood_active,
        notice=NOTICE,
        advisories=advisories,
        lat=lat,
        lng=lng,
        language="en",
    )


async def city_alerts(weather: WeatherClient) -> AlertsOut:
    """National Weather Service report for Miami, used by the widget and Watch."""
    return await alerts_for(weather, MIAMI_LAT, MIAMI_LNG, "Miami")

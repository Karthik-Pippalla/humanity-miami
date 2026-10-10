import json
from functools import lru_cache
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / "data"
BUDGET_RANK = {"free": 0, "low": 1, "medium": 2, "high": 3}
CONFIRM = "Confirm this site is open with Miami-Dade before you go. Shelter locations change during an emergency."


@lru_cache
def load_resources() -> tuple[dict, ...]:
    return tuple(json.loads((DATA / "miami_resources.json").read_text()))


@lru_cache
def load_attractions() -> tuple[dict, ...]:
    return tuple(json.loads((DATA / "miami_attractions.json").read_text()))


def attraction_by_id() -> dict[str, dict]:
    return {item["id"]: item for item in load_attractions()}


def search_attractions(
    interests: list[str],
    budget: str,
    vibe: str,
    needs: list[str],
    age: int,
) -> tuple[list[dict], bool]:
    """Return catalog places the profile can use. The second flag means filters were relaxed."""
    rank = BUDGET_RANK.get(budget, BUDGET_RANK["medium"])
    wanted = {item.strip().casefold() for item in interests if item.strip()}
    need_set = {item.strip().casefold() for item in needs}
    strict = _rank(load_attractions(), rank, wanted, vibe, need_set, age, require_interest=bool(wanted))
    if strict or not wanted:
        return strict[:8], False
    relaxed = _rank(load_attractions(), rank, set(), vibe, need_set, age, require_interest=False)
    return relaxed[:8], True


def _rank(places, rank, wanted, vibe, needs, age, require_interest: bool) -> list[dict]:
    scored: list[tuple[int, str, dict]] = []
    vibe_name = vibe.strip().casefold()
    for place in places:
        if BUDGET_RANK.get(place["budget"], 2) > rank:
            continue
        if "wheelchair" in needs and not place.get("wheelchair"):
            continue
        if ("elderly" in needs or age >= 65) and not (place.get("low_walking") or place.get("wheelchair")):
            continue
        tags = {tag.casefold() for tag in place.get("interests") or []}
        overlap = wanted & tags
        if require_interest and not overlap:
            continue
        score = len(overlap) * 3 + (2 if vibe_name in {item.casefold() for item in place.get("vibes") or []} else 0)
        if age <= 12 and "family" in {item.casefold() for item in place.get("vibes") or []}:
            score += 2
        if not wanted:
            score += 1
        scored.append((score, place["name"], place))
    scored.sort(key=lambda item: (-item[0], item[1]))
    return [place for _, _, place in scored]


def matching_resources(needs: list[str]) -> list[dict]:
    wanted = {item.strip().casefold() for item in needs} - {"no_car"}
    chosen = []
    for resource in load_resources():
        serves = {item.casefold() for item in resource.get("serves") or []}
        if wanted and not (serves & wanted) and "general" not in serves:
            continue
        chosen.append(resource)
    return chosen

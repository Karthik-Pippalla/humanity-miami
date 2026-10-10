LANGUAGES = {
    "en": "English",
    "es": "Spanish",
    "ht": "Haitian Creole",
}


def normalize_language(value: str | None) -> str:
    code = (value or "en").strip().lower()
    if code in LANGUAGES:
        return code
    return "en"


def language_clause(value: str | None) -> str:
    name = LANGUAGES[normalize_language(value)]
    return (
        f"Write in {name}. This text is an explanation, not an official translation. "
        "Keep official alert titles and place names as they appear in the facts."
    )

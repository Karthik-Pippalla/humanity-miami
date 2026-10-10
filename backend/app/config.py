from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


def repo_root() -> Path:
    here = Path(__file__).resolve()
    for parent in here.parents:
        if (parent / "backend").is_dir() and (parent / "web").is_dir():
            return parent
    return here.parents[2]


ROOT = repo_root()
ENV_FILE = ROOT / ".env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=str(ENV_FILE) if ENV_FILE.exists() else None,
        extra="ignore",
    )

    google_maps_api_key: str = ""
    ticketmaster_api_key: str = ""
    gemini_api_key: str = ""
    valhalla_url: str = "https://valhalla1.openstreetmap.de"
    gemma_model: str = "gemma-4-26b-a4b-it"
    nws_user_agent: str = "MapMiami/1.0 (local development)"
    cors_origins: str = "http://localhost:5173,http://127.0.0.1:5173"
    cache_path: str = str(ROOT / "backend" / "data" / "cache.sqlite")

    @property
    def cors_origin_list(self) -> list[str]:
        return [item.strip() for item in self.cors_origins.split(",") if item.strip()]


settings = Settings()

import sqlite3
import time
from pathlib import Path


class SqliteCache:
    def __init__(self, path: str):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS cache (
                    key TEXT PRIMARY KEY,
                    payload TEXT NOT NULL,
                    expires_at INTEGER NOT NULL
                )
                """
            )

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path)
        conn.row_factory = sqlite3.Row
        return conn

    def get(self, key: str) -> str | None:
        now = int(time.time())
        with self._connect() as conn:
            row = conn.execute("SELECT payload, expires_at FROM cache WHERE key = ?", (key,)).fetchone()
            if row is None or row["expires_at"] < now:
                return None
            return row["payload"]

    def set(self, key: str, payload: str, ttl_seconds: int) -> None:
        expires = int(time.time()) + ttl_seconds
        with self._connect() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO cache (key, payload, expires_at) VALUES (?, ?, ?)",
                (key, payload, expires),
            )

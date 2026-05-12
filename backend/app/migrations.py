from __future__ import annotations

from sqlalchemy import inspect, text

from .config import get_settings
from .database import engine


settings = get_settings()


SQLITE_COLUMN_MIGRATIONS: dict[str, dict[str, str]] = {
    "devices": {
        "led1_working": "BOOLEAN",
        "led2_working": "BOOLEAN",
        "led3_working": "BOOLEAN",
        "auto_lights_enabled": "BOOLEAN DEFAULT 0",
        "auto_light_threshold": "INTEGER",
    },
    "telemetry_events": {
        "led1_working": "BOOLEAN",
        "led2_working": "BOOLEAN",
        "led3_working": "BOOLEAN",
    },
}


def ensure_runtime_schema() -> None:
    if not settings.is_sqlite:
        return

    with engine.begin() as connection:
        inspector = inspect(connection)
        table_names = set(inspector.get_table_names())
        for table_name, columns in SQLITE_COLUMN_MIGRATIONS.items():
            if table_name not in table_names:
                continue
            existing_columns = {column["name"] for column in inspector.get_columns(table_name)}
            for column_name, column_type in columns.items():
                if column_name in existing_columns:
                    continue
                connection.execute(text(f"ALTER TABLE {table_name} ADD COLUMN {column_name} {column_type}"))

from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "Street Light Backend"
    api_prefix: str = "/api/v1"
    secret_key: str = "change-this-secret-key"
    access_token_expire_minutes: int = 60 * 24
    database_url: str = "sqlite:///./streetlight.db"
    cors_origins: str = "http://localhost:3000,http://localhost:8080"

    mqtt_host: str = "127.0.0.1"
    mqtt_port: int = 1883
    mqtt_username: str = "streetlight"
    mqtt_password: str = ""
    mqtt_client_id: str = "streetlight-backend"
    mqtt_telemetry_topic: str = "streetlight/+/telemetry"
    mqtt_status_topic: str = "streetlight/+/status"
    mqtt_command_topic_template: str = "streetlight/{device_id}/command"
    mqtt_command_qos: int = 1
    mqtt_command_retain: bool = True

    default_admin_username: str = "admin"
    default_admin_password: str = "admin1234"

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", case_sensitive=False)

    @property
    def is_sqlite(self) -> bool:
        return self.database_url.startswith("sqlite")

    @property
    def cors_origins_list(self) -> list[str]:
        value = self.cors_origins.strip()
        if value.startswith("[") and value.endswith("]"):
            import json

            loaded = json.loads(value)
            if isinstance(loaded, list):
                return [str(item).strip() for item in loaded if str(item).strip()]
        return [item.strip() for item in value.split(",") if item.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()

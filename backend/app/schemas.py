from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, model_validator


class LoginRequest(BaseModel):
    username: str = Field(min_length=3, max_length=64)
    password: str = Field(min_length=4, max_length=128)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int


class UserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    username: str
    is_active: bool


class FaultyLed(BaseModel):
    channel: str
    reason: str
    reading: int | None
    working: bool | None = None
    expected: bool | None = None


class DeviceSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str | None
    last_seen_at: datetime | None
    last_period: str | None
    ambient_value: int | None
    ambient_source: str | None
    has_fault: bool
    led1_reading: int | None
    led2_reading: int | None
    led3_reading: int | None
    led1_working: bool | None
    led2_working: bool | None
    led3_working: bool | None
    led1_expected: bool | None
    led2_expected: bool | None
    led3_expected: bool | None
    auto_lights_enabled: bool = False
    auto_light_threshold: int | None
    last_command_at: datetime | None
    created_at: datetime


class DeviceDetail(DeviceSummary):
    last_telemetry_payload: dict[str, Any] | None
    last_status_payload: dict[str, Any] | None
    last_fault_payload: dict[str, Any] | None


class TelemetryRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    device_id: str
    ambient_ldr: int | None
    ldr1: int | None
    ldr2: int | None
    ldr3: int | None
    led1_working: bool | None
    led2_working: bool | None
    led3_working: bool | None
    led1_expected: bool | None
    led2_expected: bool | None
    led3_expected: bool | None
    raw_payload: dict[str, Any]
    received_at: datetime


class FaultRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    device_id: str
    has_fault: bool
    faulty_leds: list[FaultyLed]
    raw_payload: dict[str, Any]
    received_at: datetime


class StatusRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    device_id: str
    source_topic: str
    period: str | None
    ambient_value: int | None
    ambient_source: str | None
    raw_payload: dict[str, Any]
    received_at: datetime


class DeviceCommandRequest(BaseModel):
    led1_expected: bool | None = None
    led2_expected: bool | None = None
    led3_expected: bool | None = None
    auto_lights_enabled: bool | None = None
    auto_light_threshold: int | None = Field(default=None, ge=0, le=4095)
    note: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def ensure_any_change(self) -> "DeviceCommandRequest":
        requested_values = (
            self.led1_expected,
            self.led2_expected,
            self.led3_expected,
            self.auto_lights_enabled,
            self.auto_light_threshold,
        )
        if all(value is None for value in requested_values):
            raise ValueError("At least one LED state or auto-light setting must be provided")
        if self.auto_lights_enabled is True and self.auto_light_threshold is None:
            raise ValueError("auto_light_threshold is required when auto_lights_enabled is true")
        return self


class CommandRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    command_id: str
    device_id: str
    source_topic: str
    command_name: str
    requested_by: str
    status: str
    raw_payload: dict[str, Any]
    response_payload: dict[str, Any] | None
    note: str | None
    created_at: datetime
    acknowledged_at: datetime | None


class DashboardSummary(BaseModel):
    total_devices: int
    online_devices: int
    devices_with_faults: int
    telemetry_events_last_24h: int


class RealtimeEnvelope(BaseModel):
    type: str
    device_id: str | None
    payload: dict[str, Any]
    timestamp: datetime

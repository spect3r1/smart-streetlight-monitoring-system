from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from sqlalchemy import JSON, Boolean, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from .database import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    username: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Device(Base):
    __tablename__ = "devices"

    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    name: Mapped[str | None] = mapped_column(String(128), nullable=True)
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
    last_period: Mapped[str | None] = mapped_column(String(32), nullable=True)
    ambient_value: Mapped[int | None] = mapped_column(Integer, nullable=True)
    ambient_source: Mapped[str | None] = mapped_column(String(64), nullable=True)
    has_fault: Mapped[bool] = mapped_column(Boolean, default=False)
    led1_reading: Mapped[int | None] = mapped_column(Integer, nullable=True)
    led2_reading: Mapped[int | None] = mapped_column(Integer, nullable=True)
    led3_reading: Mapped[int | None] = mapped_column(Integer, nullable=True)
    led1_working: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    led2_working: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    led3_working: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    led1_expected: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    led2_expected: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    led3_expected: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    auto_lights_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    auto_light_threshold: Mapped[int | None] = mapped_column(Integer, nullable=True)
    last_telemetry_payload: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    last_status_payload: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    last_fault_payload: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    last_command_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class TelemetryEvent(Base):
    __tablename__ = "telemetry_events"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    device_id: Mapped[str] = mapped_column(ForeignKey("devices.id"), index=True)
    source_topic: Mapped[str] = mapped_column(String(255))
    ambient_ldr: Mapped[int | None] = mapped_column(Integer, nullable=True)
    ldr1: Mapped[int | None] = mapped_column(Integer, nullable=True)
    ldr2: Mapped[int | None] = mapped_column(Integer, nullable=True)
    ldr3: Mapped[int | None] = mapped_column(Integer, nullable=True)
    led1_working: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    led2_working: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    led3_working: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    led1_expected: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    led2_expected: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    led3_expected: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    raw_payload: Mapped[dict[str, Any]] = mapped_column(JSON)
    received_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)


class StatusEvent(Base):
    __tablename__ = "status_events"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    device_id: Mapped[str] = mapped_column(ForeignKey("devices.id"), index=True)
    source_topic: Mapped[str] = mapped_column(String(255))
    period: Mapped[str | None] = mapped_column(String(32), nullable=True)
    ambient_value: Mapped[int | None] = mapped_column(Integer, nullable=True)
    ambient_source: Mapped[str | None] = mapped_column(String(64), nullable=True)
    raw_payload: Mapped[dict[str, Any]] = mapped_column(JSON)
    received_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)


class FaultEvent(Base):
    __tablename__ = "fault_events"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    device_id: Mapped[str] = mapped_column(ForeignKey("devices.id"), index=True)
    source_topic: Mapped[str] = mapped_column(String(255))
    has_fault: Mapped[bool] = mapped_column(Boolean, default=False)
    faulty_leds: Mapped[list[dict[str, Any]]] = mapped_column(JSON)
    raw_payload: Mapped[dict[str, Any]] = mapped_column(JSON)
    received_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)


class CommandEvent(Base):
    __tablename__ = "command_events"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    command_id: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    device_id: Mapped[str] = mapped_column(ForeignKey("devices.id"), index=True)
    source_topic: Mapped[str] = mapped_column(String(255))
    command_name: Mapped[str] = mapped_column(String(64), default="device_command")
    requested_by: Mapped[str] = mapped_column(String(64))
    status: Mapped[str] = mapped_column(String(32), default="queued")
    raw_payload: Mapped[dict[str, Any]] = mapped_column(JSON)
    response_payload: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)
    acknowledged_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

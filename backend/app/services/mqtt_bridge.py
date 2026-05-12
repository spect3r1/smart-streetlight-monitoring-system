from __future__ import annotations

import asyncio
import json
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

import paho.mqtt.client as mqtt
from sqlalchemy import select

from .. import models
from ..config import get_settings
from ..database import SessionLocal
from ..schemas import CommandRead, RealtimeEnvelope
from .realtime import RealtimeHub
from .telemetry_rules import build_fault_payload, coerce_bool, coerce_int, isoformat_utc


settings = get_settings()


def parse_timestamp(value: Any) -> datetime:
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            pass
    return datetime.now(timezone.utc)


class MQTTBridge:
    def __init__(self, realtime_hub: RealtimeHub) -> None:
        self.realtime_hub = realtime_hub
        self.client: mqtt.Client | None = None
        self.loop: asyncio.AbstractEventLoop | None = None
        self.is_connected = False

    def start(self, loop: asyncio.AbstractEventLoop) -> None:
        self.loop = loop
        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=settings.mqtt_client_id)
        self.client.username_pw_set(settings.mqtt_username, settings.mqtt_password)
        self.client.reconnect_delay_set(min_delay=1, max_delay=15)
        self.client.on_connect = self._on_connect
        self.client.on_disconnect = self._on_disconnect
        self.client.on_message = self._on_message
        self.client.connect_async(settings.mqtt_host, settings.mqtt_port, keepalive=60)
        self.client.loop_start()

    def stop(self) -> None:
        if self.client is None:
            return
        self.client.loop_stop()
        self.client.disconnect()
        self.is_connected = False

    def publish_expected_state(
        self,
        device_id: str,
        led_expected: dict[str, bool | None],
        requested_by: str,
        note: str | None = None,
        auto_lights_enabled: bool | None = None,
        auto_light_threshold: int | None = None,
    ) -> tuple[CommandRead, RealtimeEnvelope]:
        if self.client is None or not self.is_connected:
            raise RuntimeError("MQTT broker is not connected")

        issued_at = datetime.now(timezone.utc)
        topic = settings.mqtt_command_topic_template.format(device_id=device_id)

        with SessionLocal.begin() as session:
            device = session.get(models.Device, device_id)
            if device is None:
                raise LookupError("Device not found")

            led1_expected = self._resolve_expected_state(device.led1_expected, led_expected.get("led1_expected"))
            led2_expected = self._resolve_expected_state(device.led2_expected, led_expected.get("led2_expected"))
            led3_expected = self._resolve_expected_state(device.led3_expected, led_expected.get("led3_expected"))
            resolved_auto_enabled = device.auto_lights_enabled if auto_lights_enabled is None else auto_lights_enabled
            resolved_auto_threshold = device.auto_light_threshold if auto_light_threshold is None else auto_light_threshold

            command_payload = {
                "command_id": uuid4().hex,
                "command": "set_expected_state",
                "device_id": device_id,
                "led1_expected": int(led1_expected),
                "led2_expected": int(led2_expected),
                "led3_expected": int(led3_expected),
                "auto_lights_enabled": int(bool(resolved_auto_enabled)),
                "auto_light_threshold": resolved_auto_threshold,
                "ts": isoformat_utc(issued_at),
            }
            if note:
                command_payload["note"] = note

            message_info = self.client.publish(
                topic,
                json.dumps(command_payload),
                qos=settings.mqtt_command_qos,
                retain=settings.mqtt_command_retain,
            )
            if message_info.rc != mqtt.MQTT_ERR_SUCCESS:
                raise RuntimeError("Failed to publish MQTT command")
            message_info.wait_for_publish()

            device.led1_expected = led1_expected
            device.led2_expected = led2_expected
            device.led3_expected = led3_expected
            device.auto_lights_enabled = bool(resolved_auto_enabled)
            device.auto_light_threshold = resolved_auto_threshold
            device.last_command_at = issued_at

            command_event = models.CommandEvent(
                command_id=command_payload["command_id"],
                device_id=device_id,
                source_topic=topic,
                command_name="set_expected_state",
                requested_by=requested_by,
                status="sent",
                raw_payload=command_payload,
                note=note,
                created_at=issued_at,
            )
            session.add(command_event)
            session.flush()

            response_model = CommandRead.model_validate(command_event)

        envelope = RealtimeEnvelope(
            type="device.command",
            device_id=device_id,
            payload=command_payload,
            timestamp=issued_at,
        )
        return response_model, envelope

    def _maybe_publish_auto_light_command(
        self,
        device_id: str,
        ambient_value: int | None,
        received_at: datetime,
    ) -> RealtimeEnvelope | None:
        if ambient_value is None or self.client is None or not self.is_connected:
            return None

        with SessionLocal() as session:
            device = session.get(models.Device, device_id)
            if device is None or not device.auto_lights_enabled or device.auto_light_threshold is None:
                return None
            target_on = ambient_value <= device.auto_light_threshold
            current_states = (device.led1_expected, device.led2_expected, device.led3_expected)
            if current_states == (target_on, target_on, target_on):
                return None

        try:
            _, envelope = self.publish_expected_state(
                device_id=device_id,
                led_expected={
                    "led1_expected": target_on,
                    "led2_expected": target_on,
                    "led3_expected": target_on,
                },
                requested_by="auto-light",
                note=(
                    f"Auto light {'ON' if target_on else 'OFF'} because ambient LDR "
                    f"{ambient_value} {'<=' if target_on else '>'} threshold. "
                    f"Telemetry received at {isoformat_utc(received_at)}."
                ),
            )
        except (LookupError, RuntimeError):
            return None
        return envelope

    def _resolve_expected_state(self, current: bool | None, requested: bool | None) -> bool:
        if requested is not None:
            return requested
        if current is not None:
            return current
        return False

    def _on_connect(self, client: mqtt.Client, userdata, flags, reason_code, properties) -> None:
        self.is_connected = reason_code == 0
        if not self.is_connected:
            return
        client.subscribe(settings.mqtt_telemetry_topic, qos=1)
        client.subscribe(settings.mqtt_status_topic, qos=1)

    def _on_disconnect(self, client: mqtt.Client, userdata, flags, reason_code, properties) -> None:
        self.is_connected = False

    def _on_message(self, client: mqtt.Client, userdata, msg: mqtt.MQTTMessage) -> None:
        try:
            payload = json.loads(msg.payload.decode("utf-8"))
        except json.JSONDecodeError:
            return

        parts = msg.topic.split("/")
        if len(parts) < 3:
            return
        device_id = parts[1]
        event_name = parts[2]

        if event_name == "telemetry":
            envelopes = self._store_telemetry(device_id, msg.topic, payload)
        elif event_name == "status":
            envelopes = self._store_status(device_id, msg.topic, payload)
        else:
            return

        if self.loop is not None:
            for envelope in envelopes:
                asyncio.run_coroutine_threadsafe(self.realtime_hub.broadcast(envelope), self.loop)

    def _get_or_create_device(self, session, device_id: str) -> models.Device:
        device = session.get(models.Device, device_id)
        if device is None:
            device = models.Device(id=device_id)
            session.add(device)
            session.flush()
        return device

    def _store_telemetry(self, device_id: str, topic: str, payload: dict[str, Any]) -> list[RealtimeEnvelope]:
        received_at = parse_timestamp(payload.get("ts"))
        fault_payload = build_fault_payload(device_id, payload, received_at)
        with SessionLocal.begin() as session:
            device = self._get_or_create_device(session, device_id)
            device.last_seen_at = received_at
            device.led1_reading = coerce_int(payload.get("ldr1"))
            device.led2_reading = coerce_int(payload.get("ldr2"))
            device.led3_reading = coerce_int(payload.get("ldr3"))
            device.led1_working = coerce_bool(payload.get("led1_working"))
            device.led2_working = coerce_bool(payload.get("led2_working"))
            device.led3_working = coerce_bool(payload.get("led3_working"))
            device.led1_expected = coerce_bool(payload.get("led1_expected"))
            device.led2_expected = coerce_bool(payload.get("led2_expected"))
            device.led3_expected = coerce_bool(payload.get("led3_expected"))
            if "ambient_ldr" in payload:
                device.ambient_value = coerce_int(payload.get("ambient_ldr"))
                device.ambient_source = "ambient_ldr"
            device.last_telemetry_payload = payload
            device.has_fault = bool(fault_payload["fault"])
            device.last_fault_payload = fault_payload

            session.add(
                models.TelemetryEvent(
                    device_id=device_id,
                    source_topic=topic,
                    ambient_ldr=coerce_int(payload.get("ambient_ldr")),
                    ldr1=coerce_int(payload.get("ldr1")),
                    ldr2=coerce_int(payload.get("ldr2")),
                    ldr3=coerce_int(payload.get("ldr3")),
                    led1_working=coerce_bool(payload.get("led1_working")),
                    led2_working=coerce_bool(payload.get("led2_working")),
                    led3_working=coerce_bool(payload.get("led3_working")),
                    led1_expected=coerce_bool(payload.get("led1_expected")),
                    led2_expected=coerce_bool(payload.get("led2_expected")),
                    led3_expected=coerce_bool(payload.get("led3_expected")),
                    raw_payload=payload,
                    received_at=received_at,
                )
            )
            session.add(
                models.FaultEvent(
                    device_id=device_id,
                    source_topic=topic,
                    has_fault=bool(fault_payload["fault"]),
                    faulty_leds=fault_payload["faulty_leds"],
                    raw_payload=fault_payload,
                    received_at=received_at,
                )
            )

        envelopes = [
            RealtimeEnvelope(
                type="device.telemetry",
                device_id=device_id,
                payload=payload,
                timestamp=received_at,
            ),
            RealtimeEnvelope(
                type="device.fault",
                device_id=device_id,
                payload=fault_payload,
                timestamp=received_at,
            ),
        ]
        auto_value = coerce_int(payload.get("ambient_ldr"))
        if auto_value is None:
            ldr_values = [
                coerce_int(payload.get("ldr1")),
                coerce_int(payload.get("ldr2")),
                coerce_int(payload.get("ldr3")),
            ]
            available_values = [value for value in ldr_values if value is not None]
            auto_value = round(sum(available_values) / len(available_values)) if available_values else None
        auto_envelope = self._maybe_publish_auto_light_command(
            device_id=device_id,
            ambient_value=auto_value,
            received_at=received_at,
        )
        if auto_envelope is not None:
            envelopes.append(auto_envelope)
        return envelopes

    def _store_status(self, device_id: str, topic: str, payload: dict[str, Any]) -> list[RealtimeEnvelope]:
        received_at = parse_timestamp(payload.get("ts"))
        status_value = payload.get("status")
        status_label = status_value if isinstance(status_value, str) and status_value.strip() else "acknowledged"

        with SessionLocal.begin() as session:
            device = self._get_or_create_device(session, device_id)
            device.last_seen_at = received_at
            device.last_status_payload = payload
            if "led1_expected" in payload:
                device.led1_expected = coerce_bool(payload.get("led1_expected"))
            if "led2_expected" in payload:
                device.led2_expected = coerce_bool(payload.get("led2_expected"))
            if "led3_expected" in payload:
                device.led3_expected = coerce_bool(payload.get("led3_expected"))

            session.add(
                models.StatusEvent(
                    device_id=device_id,
                    source_topic=topic,
                    period=payload.get("period") if isinstance(payload.get("period"), str) else None,
                    ambient_value=coerce_int(payload.get("ambient_value")),
                    ambient_source=payload.get("ambient_source") if isinstance(payload.get("ambient_source"), str) else None,
                    raw_payload=payload,
                    received_at=received_at,
                )
            )

            command_id = payload.get("command_id")
            if isinstance(command_id, str) and command_id:
                command_event = session.scalar(
                    select(models.CommandEvent).where(models.CommandEvent.command_id == command_id)
                )
                if command_event is not None:
                    device.last_command_at = received_at
                    command_event.status = status_label
                    command_event.response_payload = payload
                    command_event.acknowledged_at = received_at

        return [
            RealtimeEnvelope(
                type="device.status",
                device_id=device_id,
                payload=payload,
                timestamp=received_at,
            )
        ]

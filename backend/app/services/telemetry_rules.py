from __future__ import annotations

from datetime import datetime, timezone
from typing import Any


def coerce_int(value: Any) -> int | None:
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def coerce_bool(value: Any) -> bool | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return bool(value)
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in {"1", "true", "yes", "on"}:
            return True
        if lowered in {"0", "false", "no", "off"}:
            return False
    return None


def isoformat_utc(value: datetime) -> str:
    return value.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def build_fault_payload(device_id: str, telemetry_payload: dict[str, Any], received_at: datetime) -> dict[str, Any]:
    led_states: list[dict[str, Any]] = []
    faulty_leds: list[dict[str, Any]] = []
    readings: list[int] = []
    expected_on = 0
    working_leds = 0

    for channel in range(1, 4):
        reading = coerce_int(telemetry_payload.get(f"ldr{channel}"))
        working = coerce_bool(telemetry_payload.get(f"led{channel}_working"))
        expected = coerce_bool(telemetry_payload.get(f"led{channel}_expected"))
        is_fault = expected is True and working is False

        if reading is not None:
            readings.append(reading)
        if expected is True:
            expected_on += 1
        if working is True:
            working_leds += 1

        led_state = {
            "channel": f"led{channel}",
            "reading": reading,
            "working": working,
            "expected": expected,
            "fault": is_fault,
        }
        led_states.append(led_state)

        if is_fault:
            faulty_leds.append(
                {
                    "channel": f"led{channel}",
                    "reason": "expected_on_but_reported_not_working",
                    "reading": reading,
                    "working": working,
                    "expected": expected,
                }
            )

    average_ldr = round(sum(readings) / len(readings)) if readings else None
    return {
        "device_id": device_id,
        "fault": bool(faulty_leds),
        "faulty_leds": faulty_leds,
        "led_states": led_states,
        "summary": {
            "expected_on_leds": expected_on,
            "reported_working_leds": working_leds,
            "average_ldr": average_ldr,
        },
        "rule": "fault when led_expected is 1 and led_working is 0",
        "ts": isoformat_utc(received_at),
    }

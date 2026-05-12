from __future__ import annotations

import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker

from app import models
from app.database import Base
from app.services import mqtt_bridge
from app.services.mqtt_bridge import MQTTBridge
from app.services.realtime import RealtimeHub


class FakeMessageInfo:
    def __init__(self) -> None:
        self.rc = 0

    def wait_for_publish(self, timeout: float | None = None) -> None:
        return None


class FakeMQTTClient:
    def __init__(self) -> None:
        self.published: list[tuple[str, str, int, bool]] = []

    def publish(self, topic: str, payload: str, qos: int, retain: bool) -> FakeMessageInfo:
        self.published.append((topic, payload, qos, retain))
        return FakeMessageInfo()


class MQTTBridgeTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        database_path = Path(self.temp_dir.name) / "test.db"
        engine = create_engine(f"sqlite:///{database_path}", connect_args={"check_same_thread": False})
        Base.metadata.create_all(bind=engine)
        self.session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False, expire_on_commit=False)
        self.original_session_local = mqtt_bridge.SessionLocal
        mqtt_bridge.SessionLocal = self.session_factory

    def tearDown(self) -> None:
        mqtt_bridge.SessionLocal = self.original_session_local
        self.temp_dir.cleanup()

    def test_publish_expected_state_stores_command_and_updates_device(self) -> None:
        with self.session_factory.begin() as session:
            session.add(models.Device(id="esp32-01", led1_expected=False, led2_expected=False, led3_expected=False))

        bridge = MQTTBridge(RealtimeHub())
        bridge.client = FakeMQTTClient()
        bridge.is_connected = True

        command, envelope = bridge.publish_expected_state(
            device_id="esp32-01",
            led_expected={"led1_expected": True, "led2_expected": False, "led3_expected": True},
            requested_by="admin",
            note="console update",
        )

        self.assertEqual(command.device_id, "esp32-01")
        self.assertEqual(command.status, "sent")
        self.assertEqual(envelope.type, "device.command")
        self.assertEqual(bridge.client.published[0][0], "streetlight/esp32-01/command")
        self.assertEqual(bridge.client.published[0][2], 1)
        self.assertTrue(bridge.client.published[0][3])

        with self.session_factory() as session:
            device = session.get(models.Device, "esp32-01")
            self.assertIsNotNone(device)
            self.assertTrue(device.led1_expected)
            self.assertFalse(device.led2_expected)
            self.assertTrue(device.led3_expected)
            stored_command = session.scalar(
                select(models.CommandEvent).where(models.CommandEvent.command_id == command.command_id)
            )
            self.assertIsNotNone(stored_command)
            self.assertEqual(stored_command.note, "console update")

    def test_status_acknowledgement_updates_command_event(self) -> None:
        created_at = datetime(2025, 4, 22, 20, 0, tzinfo=timezone.utc)
        with self.session_factory.begin() as session:
            session.add(models.Device(id="esp32-01"))
            session.add(
                models.CommandEvent(
                    command_id="cmd123",
                    device_id="esp32-01",
                    source_topic="streetlight/esp32-01/command",
                    command_name="set_expected_state",
                    requested_by="admin",
                    status="sent",
                    raw_payload={"command_id": "cmd123"},
                    created_at=created_at,
                )
            )

        bridge = MQTTBridge(RealtimeHub())
        envelopes = bridge._store_status(
            "esp32-01",
            "streetlight/esp32-01/status",
            {
                "device_id": "esp32-01",
                "command_id": "cmd123",
                "status": "applied",
                "led1_expected": 1,
                "led2_expected": 0,
                "led3_expected": 1,
                "ts": "2025-04-22T20:00:05Z",
            },
        )

        self.assertEqual(len(envelopes), 1)
        self.assertEqual(envelopes[0].type, "device.status")

        with self.session_factory() as session:
            device = session.get(models.Device, "esp32-01")
            self.assertIsNotNone(device)
            self.assertEqual(device.last_status_payload["command_id"], "cmd123")
            self.assertTrue(device.led1_expected)
            self.assertFalse(device.led2_expected)
            self.assertTrue(device.led3_expected)

            command = session.scalar(select(models.CommandEvent).where(models.CommandEvent.command_id == "cmd123"))
            self.assertIsNotNone(command)
            self.assertEqual(command.status, "applied")
            self.assertEqual(command.response_payload["status"], "applied")
            self.assertIsNotNone(command.acknowledged_at)

    def test_store_telemetry_marks_fault_when_expected_but_not_working(self) -> None:
        bridge = MQTTBridge(RealtimeHub())
        envelopes = bridge._store_telemetry(
            "esp32-01",
            "streetlight/esp32-01/telemetry",
            {
                "device_id": "esp32-01",
                "ldr1": 1860,
                "ldr2": 1795,
                "ldr3": 95,
                "led1_working": 1,
                "led2_working": 1,
                "led3_working": 0,
                "led1_expected": 1,
                "led2_expected": 1,
                "led3_expected": 1,
                "ts": "2025-04-22T20:00:00Z",
            },
        )

        self.assertEqual([envelope.type for envelope in envelopes], ["device.telemetry", "device.fault"])

        with self.session_factory() as session:
            device = session.get(models.Device, "esp32-01")
            self.assertIsNotNone(device)
            self.assertTrue(device.has_fault)
            self.assertFalse(device.led3_working)
            self.assertTrue(device.last_fault_payload["fault"])
            self.assertEqual(device.last_fault_payload["faulty_leds"][0]["channel"], "led3")


if __name__ == "__main__":
    unittest.main()

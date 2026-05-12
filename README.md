# Smart Streetlight Monitoring System

An end-to-end IoT streetlight monitoring and control platform built with:

- `ESP32` firmware for field devices
- `FastAPI` for the backend API and MQTT bridge
- `Flutter` for the mobile dashboard and operator controls
- `Mosquitto` as the MQTT broker

This project is organized as one system. The device publishes telemetry, the backend stores state and issues commands, and the Flutter app gives operators a live dashboard for monitoring and control.

## Important Notes

- `backend-new/` is the active backend implementation.
- `backend/` is an older version kept in the repo as legacy reference.
- The current ESP32 sketch contains hardcoded WiFi and MQTT credentials. Rotate or remove those secrets before publishing this repository publicly.

## Features

- Live telemetry ingestion over MQTT
- Device command delivery over retained MQTT topics
- LED fault detection based on expected state versus reported working state
- Command history and acknowledgement tracking
- JWT-based authentication for the API and app
- WebSocket realtime updates for dashboards
- Mobile-friendly Flutter app for login, fleet overview, and device control
- Optional backend-driven auto-light mode using an ambient threshold

## Repository Layout

```text
.
|-- README.md
|-- deploy/
|   `-- mosquitto.conf
|-- backend/                  # legacy backend
|-- backend-new/              # active FastAPI backend
|   |-- app/
|   |-- deploy/
|   `-- tests/
|-- esp32/
|   |-- README.md
|   `-- streetlight_controller/
|-- flutter_app/
|   |-- lib/
|   |-- android/
|   |-- ios/
|   `-- test/
`-- .tooling/                 # local tooling/runtime assets
```

## Architecture

```text
ESP32 device
  |- reads 3 LDR sensors
  |- reads 3 LED feedback pins
  |- publishes telemetry/status over MQTT
  `- receives retained LED commands

Mosquitto broker
  |- streetlight/<device_id>/telemetry
  |- streetlight/<device_id>/status
  `- streetlight/<device_id>/command

FastAPI backend in backend-new/
  |- subscribes to telemetry/status topics
  |- stores device snapshots and event history in SQLite
  |- computes fault events
  |- publishes commands back to devices
  `- exposes REST + WebSocket APIs

Flutter app
  |- authenticates with the backend
  |- shows dashboard and device details
  `- sends operator commands and listens for realtime updates
```

## End-to-End Flow

1. The ESP32 connects to WiFi, syncs time with NTP, connects to MQTT, and subscribes to its command topic.
2. Every 5 seconds it publishes telemetry containing LDR readings, LED feedback, and the current expected LED states.
3. The backend stores the telemetry, updates the latest device snapshot, and evaluates fault rules.
4. If an operator sends a command from the app, the backend publishes a retained MQTT command for that device and stores a command record.
5. The ESP32 applies the requested LED states, publishes a status acknowledgement, and immediately republishes telemetry.
6. The backend updates command status, stores the acknowledgement, and broadcasts realtime events to connected dashboards over WebSocket.

## MQTT Contract

### Telemetry Topic

```text
streetlight/<device_id>/telemetry
```

Example payload:

```json
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
  "ts": "2025-04-22T20:00:00Z"
}
```

### Command Topic

```text
streetlight/<device_id>/command
```

Example payload:

```json
{
  "command_id": "9f6b9b8a1c284725a3fba6c9efba3d4f",
  "command": "set_expected_state",
  "device_id": "esp32-01",
  "led1_expected": 1,
  "led2_expected": 0,
  "led3_expected": 1,
  "auto_lights_enabled": 1,
  "auto_light_threshold": 1800,
  "note": "manual override",
  "ts": "2025-04-22T20:00:05Z"
}
```

### Status Topic

```text
streetlight/<device_id>/status
```

Example payload:

```json
{
  "device_id": "esp32-01",
  "command_id": "9f6b9b8a1c284725a3fba6c9efba3d4f",
  "status": "applied",
  "led1_expected": 1,
  "led2_expected": 0,
  "led3_expected": 1,
  "ts": "2025-04-22T20:00:06Z"
}
```

## Fault Detection Logic

The backend currently uses this rule:

```text
fault when led_expected == 1 and led_working == 0
```

For each telemetry event the backend builds a fault summary, stores it, and marks the device as faulty if any LED channel is expected to be on but reports not working.

## How the Active Backend Works

Source of truth: `backend-new/`

- `app/main.py` starts FastAPI, creates database tables, ensures the default admin exists, and starts the MQTT bridge.
- `app/services/mqtt_bridge.py` subscribes to telemetry and status topics, stores incoming events, and publishes outgoing commands.
- `app/services/telemetry_rules.py` normalizes values and computes the fault payload.
- `app/models.py` defines device, telemetry, status, command, fault, and user tables.
- `app/auth.py` provides JWT login and request authentication.
- `app/static/console.html` is a built-in browser console served at `/console`.

### Backend Realtime Events

The WebSocket stream at `/ws/stream?token=<jwt>` emits these event types:

- `session.ready`
- `device.telemetry`
- `device.fault`
- `device.status`
- `device.command`

### Auto-Light Mode

Auto-light mode is implemented by the backend, not by the ESP32 firmware logic.

- When auto mode is enabled, the backend compares ambient light against `auto_light_threshold`.
- If `ambient_ldr` is missing, it falls back to the average of `ldr1`, `ldr2`, and `ldr3`.
- The backend then publishes a normal LED state command turning all channels on or off together.
- The current ESP32 sketch ignores the `auto_lights_enabled` and `auto_light_threshold` fields in the command payload itself; it only applies the resolved LED states sent by the backend.

## How the ESP32 Firmware Works

Source of truth: `esp32/streetlight_controller/streetlight_controller.ino`

### Pin Map

- `GPIO25`: LED 1 output
- `GPIO26`: LED 2 output
- `GPIO27`: LED 3 output
- `GPIO34`: LDR 1 analog input
- `GPIO35`: LDR 2 analog input
- `GPIO32`: LDR 3 analog input
- `GPIO18`: LED 1 feedback input
- `GPIO19`: LED 2 feedback input
- `GPIO23`: LED 3 feedback input

### Firmware Lifecycle

1. `setupPins()` configures outputs, feedback inputs, and ADC resolution.
2. `applyExpectedStates(true, true, true)` initializes all three LED outputs to on.
3. `connectWifi()` retries WiFi connection every 3 seconds until connected.
4. `syncClock()` configures NTP so telemetry and status messages can include UTC timestamps.
5. `connectMqtt()` connects to the broker, subscribes to `streetlight/<device_id>/command`, then publishes an `online` status and initial telemetry.
6. `loop()` keeps MQTT alive and publishes telemetry every 5 seconds.
7. `mqttCallback()` handles incoming retained commands for that device only.
8. `handleCommand()` updates the expected LED states, writes GPIO outputs, publishes an `applied` status, and immediately sends fresh telemetry.

### What the Firmware Measures

- `ldr1`, `ldr2`, `ldr3` come from analog sensor reads.
- `led1_working`, `led2_working`, `led3_working` come from digital feedback pins.
- `led1_expected`, `led2_expected`, `led3_expected` reflect the device's current local command state.

### Debugging Behavior

`DEBUG_ENABLED` is currently set to `true`, so the sketch prints detailed WiFi, MQTT, telemetry, and command logs over the serial monitor.

## How the Flutter App Works

Source of truth: `flutter_app/`

- The app logs in through `POST /api/v1/auth/login`.
- The JWT is stored with `shared_preferences`.
- `ApiClient` adds the bearer token to authenticated requests.
- `RealtimeService` opens a WebSocket connection to `/ws/stream`.
- The dashboard screen shows fleet-level metrics and device cards.
- The device detail screen shows telemetry, status, fault, and command history and can send new commands.

### Flutter Screens

- Login screen
- Dashboard summary screen
- Device detail screen with command form and history panels

### Flutter Backend Configuration

The default backend URL is currently:

```text
http://104.248.227.238:8000
```

Override it at runtime:

```bash
flutter run --dart-define=API_BASE_URL=http://YOUR_BACKEND_HOST:8000
```

## Quick Start

### 1. Start Mosquitto

Install dependencies:

```bash
sudo apt update
sudo apt install -y mosquitto mosquitto-clients python3 python3-venv
```

Minimal config based on `deploy/mosquitto.conf`:

```bash
sudo mkdir -p /etc/mosquitto/conf.d
sudo cp deploy/mosquitto.conf /etc/mosquitto/conf.d/streetlight.conf
sudo mosquitto_passwd -c /etc/mosquitto/passwd streetlight
sudo systemctl restart mosquitto
```

### 2. Run the Active Backend

```bash
cd backend-new
python3 -m venv .venv
.venv/bin/pip install -e .[dev]
cp deploy/streetlight-backend.env.example .env
```

Edit `.env` and set at least:

- `SECRET_KEY`
- `MQTT_PASSWORD`
- `DEFAULT_ADMIN_PASSWORD`
- `CORS_ORIGINS`
- `DATABASE_URL` if you do not want the default local SQLite file

Start the API:

```bash
.venv/bin/uvicorn app.main:app --reload
```

Useful URLs:

- `http://127.0.0.1:8000/docs`
- `http://127.0.0.1:8000/health`
- `http://127.0.0.1:8000/console`

Default login comes from `.env`:

- username: `DEFAULT_ADMIN_USERNAME`
- password: `DEFAULT_ADMIN_PASSWORD`

### 3. Flash the ESP32

Open `esp32/streetlight_controller/streetlight_controller.ino` in Arduino IDE or PlatformIO and review these constants before uploading:

- `WIFI_SSID`
- `WIFI_PASSWORD`
- `MQTT_HOST`
- `MQTT_PORT`
- `MQTT_USERNAME`
- `MQTT_PASSWORD`
- `DEVICE_ID`

Required Arduino libraries:

- `PubSubClient`
- `ArduinoJson`

After upload:

- open the serial monitor
- confirm WiFi connection
- confirm MQTT subscription to `streetlight/<device_id>/command`
- confirm status and telemetry are being published

### 4. Run the Flutter App

```bash
cd flutter_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

For Android emulators, a host address such as `10.0.2.2` may be more appropriate than `127.0.0.1`.

## API Quick Reference

All authenticated endpoints use a bearer token.

- `POST /api/v1/auth/login`
- `GET /api/v1/me`
- `GET /api/v1/dashboard/summary`
- `GET /api/v1/devices`
- `GET /api/v1/devices/{device_id}`
- `GET /api/v1/devices/{device_id}/telemetry`
- `GET /api/v1/devices/{device_id}/faults`
- `GET /api/v1/devices/{device_id}/status`
- `GET /api/v1/devices/{device_id}/commands`
- `POST /api/v1/devices/{device_id}/commands`
- `GET /health`
- `GET /console`
- `GET /ws/stream?token=<jwt>`

## Testing

Backend tests:

```bash
cd backend-new
.venv/bin/python -m pytest
```

Flutter checks:

```bash
cd flutter_app
flutter analyze
flutter test
```

## Deployment Notes

- `backend-new/deploy/streetlight-backend.env.example` contains a backend env template.
- `backend-new/deploy/streetlight-backend.service` contains a systemd unit.
- That systemd file assumes the deployed folder is named `/opt/streetlight-backend/backend`. If you deploy the current folder name `backend-new`, update `WorkingDirectory` and database paths accordingly.

## GitHub Readiness Checklist

Before making the repo public:

- remove or rotate hardcoded WiFi and MQTT secrets from the ESP32 sketch
- review the default backend IP in the Flutter app
- exclude generated files such as `.venv`, `build/`, `.dart_tool/`, `__pycache__/`, `.db`, and `.zip`
- decide whether to keep `backend/` in the repo or move it to an archive folder
- add screenshots if you want a stronger GitHub presentation

## Component Docs

- `backend-new/README.md`
- `esp32/README.md`
- `flutter_app/README.md`

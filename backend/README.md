# Streetlight Backend

Active backend for the smart streetlight system. This folder is the current implementation used by the Flutter app and MQTT-connected ESP32 devices.

## Responsibilities

- authenticate operators with JWT tokens
- subscribe to MQTT telemetry and status topics
- store device snapshots and event history in SQLite
- detect LED faults
- publish retained MQTT commands back to devices
- expose REST APIs for dashboards and mobile clients
- expose a WebSocket stream for realtime updates
- serve a simple built-in browser console at `/console`

## Stack

- Python `3.12+`
- FastAPI
- SQLAlchemy
- Paho MQTT
- SQLite by default

## Project Structure

```text
backend-new/
|-- app/
|   |-- auth.py
|   |-- config.py
|   |-- database.py
|   |-- main.py
|   |-- migrations.py
|   |-- models.py
|   |-- schemas.py
|   |-- services/
|   |   |-- mqtt_bridge.py
|   |   |-- realtime.py
|   |   `-- telemetry_rules.py
|   `-- static/
|       `-- console.html
|-- deploy/
|   |-- streetlight-backend.env.example
|   `-- streetlight-backend.service
`-- tests/
    `-- test_mqtt_bridge.py
```

## Local Run

```bash
python3 -m venv .venv
.venv/bin/pip install -e .[dev]
cp deploy/streetlight-backend.env.example .env
```

Start the API:

```bash
.venv/bin/uvicorn app.main:app --reload
```

Useful endpoints:

- `http://127.0.0.1:8000/docs`
- `http://127.0.0.1:8000/health`
- `http://127.0.0.1:8000/console`

## Required Configuration

Main environment variables:

- `SECRET_KEY`
- `DATABASE_URL`
- `CORS_ORIGINS`
- `MQTT_HOST`
- `MQTT_PORT`
- `MQTT_USERNAME`
- `MQTT_PASSWORD`
- `MQTT_CLIENT_ID`
- `MQTT_TELEMETRY_TOPIC`
- `MQTT_STATUS_TOPIC`
- `MQTT_COMMAND_TOPIC_TEMPLATE`
- `DEFAULT_ADMIN_USERNAME`
- `DEFAULT_ADMIN_PASSWORD`

By default the backend:

- uses SQLite
- subscribes to `streetlight/+/telemetry`
- subscribes to `streetlight/+/status`
- publishes commands to `streetlight/{device_id}/command`
- creates a default admin user on startup if one does not already exist

## API Summary

Authentication:

- `POST /api/v1/auth/login`
- `GET /api/v1/me`

Dashboard and devices:

- `GET /api/v1/dashboard/summary`
- `GET /api/v1/devices`
- `GET /api/v1/devices/{device_id}`

Device history:

- `GET /api/v1/devices/{device_id}/telemetry`
- `GET /api/v1/devices/{device_id}/faults`
- `GET /api/v1/devices/{device_id}/status`
- `GET /api/v1/devices/{device_id}/commands`

Device control:

- `POST /api/v1/devices/{device_id}/commands`

Realtime and utility:

- `GET /health`
- `GET /console`
- `GET /ws/stream?token=<jwt>`

## Command Payload Accepted by the Backend

The command endpoint accepts:

```json
{
  "led1_expected": true,
  "led2_expected": false,
  "led3_expected": true,
  "auto_lights_enabled": true,
  "auto_light_threshold": 1800,
  "note": "manual override"
}
```

Validation rules:

- at least one LED field or auto-light field must be present
- `auto_light_threshold` must be between `0` and `4095`
- if `auto_lights_enabled` is `true`, a threshold is required

## Data Stored by the Backend

The backend stores:

- `devices`: current snapshot per device
- `telemetry_events`: raw telemetry history
- `status_events`: status acknowledgements and online events
- `fault_events`: generated fault summaries
- `command_events`: commands published by operators or auto-light logic
- `users`: authenticated backend users

## Realtime Event Types

The WebSocket stream emits:

- `session.ready`
- `device.telemetry`
- `device.fault`
- `device.status`
- `device.command`

## Fault Logic

The current rule is:

```text
fault when led_expected is 1 and led_working is 0
```

Each telemetry payload is normalized, converted into a fault summary, and stored in both the device snapshot and the `fault_events` history table.

## Auto-Light Logic

Auto-light mode is backend driven.

- If enabled for a device, the backend compares ambient light to `auto_light_threshold`.
- If the measured light is below or equal to the threshold, the backend turns all LEDs on.
- If the measured light is above the threshold, the backend turns all LEDs off.
- If `ambient_ldr` is absent, the backend uses the average of `ldr1`, `ldr2`, and `ldr3`.

## Tests

Run tests with:

```bash
.venv/bin/python -m pytest
```

The current test suite covers:

- command publishing and persistence
- status acknowledgement handling
- telemetry-to-fault conversion

## Deployment

The `deploy/` directory contains:

- `streetlight-backend.env.example`: environment template
- `streetlight-backend.service`: systemd unit

The service file assumes the deployed directory path ends in `/backend`. If you deploy this folder as `backend-new`, update the service file before enabling it.

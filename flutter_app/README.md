# Streetlight Flutter App

Mobile dashboard and control client for the smart streetlight system.

The app authenticates against the active backend in `backend-new/`, displays fleet health, listens for realtime updates, and lets an operator send control commands to each device.

## Features

- login with backend credentials
- persistent session restore with `shared_preferences`
- dashboard summary for fleet health
- device list and device detail views
- command form for LED states and auto-light settings
- realtime updates over WebSocket
- Android and iOS project folders included

## Stack

- Flutter
- Dio for REST requests
- Provider for state wiring
- GoRouter for navigation
- WebSocket channel for realtime updates

## Backend Configuration

The default backend URL is hardcoded in `lib/src/core/app_config.dart`:

```text
http://104.248.227.238:8000
```

Override it at runtime:

```bash
flutter run --dart-define=API_BASE_URL=http://YOUR_BACKEND_HOST:8000
```

If the backend uses HTTPS, the app automatically switches the realtime WebSocket connection to `wss`.

## Run

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

For a physical phone, replace `127.0.0.1` with the backend machine's reachable IP address.

## Authentication Flow

1. the app posts credentials to `/api/v1/auth/login`
2. it stores the JWT token, username, and expiry data locally
3. it calls `/api/v1/me` to verify the session
4. it opens `/ws/stream?token=<jwt>` for realtime updates

## Screens

### Login

- accepts backend username and password
- shows backend errors returned from the API

### Dashboard

- shows total devices
- shows reporting devices
- shows devices with faults
- shows telemetry count in the last 24 hours
- refreshes when realtime device events arrive

### Device Detail

- loads the latest device snapshot
- loads telemetry history
- loads status history
- loads fault history
- loads command history
- lets the operator toggle `led1_expected`, `led2_expected`, and `led3_expected`
- lets the operator enable auto-light mode and set `auto_light_threshold`
- lets the operator attach an optional note to a command

## API Usage

The app currently calls:

- `POST /api/v1/auth/login`
- `GET /api/v1/me`
- `GET /api/v1/dashboard/summary`
- `GET /api/v1/devices`
- `GET /api/v1/devices/{device_id}`
- `GET /api/v1/devices/{device_id}/telemetry`
- `GET /api/v1/devices/{device_id}/status`
- `GET /api/v1/devices/{device_id}/faults`
- `GET /api/v1/devices/{device_id}/commands`
- `POST /api/v1/devices/{device_id}/commands`

## Realtime Behavior

The app listens to backend WebSocket events and refreshes when it receives device-related updates such as:

- `device.telemetry`
- `device.fault`
- `device.status`
- `device.command`

## Verification

Static analysis:

```bash
flutter analyze
```

Tests:

```bash
flutter test
```

## Notes for GitHub Upload

- `android/local.properties` should not be committed in a clean public repo.
- `build/` and `.dart_tool/` should be ignored.
- review the default backend IP before sharing the project publicly.

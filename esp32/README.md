# ESP32 Streetlight Firmware

Firmware for the field device that reads sensors, drives LED outputs, receives commands over MQTT, and reports status back to the backend.

Source sketch:

```text
esp32/streetlight_controller/streetlight_controller.ino
```

## Responsibilities

- connect to WiFi
- sync UTC time with NTP
- connect to the MQTT broker
- subscribe to retained device commands
- drive three LED output channels
- read three LDR sensor channels
- read three LED feedback pins
- publish telemetry every 5 seconds
- publish status when the device comes online or applies a command

## Hardware Pin Map

- `GPIO25`: LED 1 output
- `GPIO26`: LED 2 output
- `GPIO27`: LED 3 output
- `GPIO34`: LDR 1 analog input
- `GPIO35`: LDR 2 analog input
- `GPIO32`: LDR 3 analog input
- `GPIO18`: LED 1 working feedback input
- `GPIO19`: LED 2 working feedback input
- `GPIO23`: LED 3 working feedback input

## Libraries

- `WiFi.h`
- `PubSubClient`
- `ArduinoJson`
- `time.h`

## Configurable Constants

Near the top of the sketch you will find:

- `WIFI_SSID`
- `WIFI_PASSWORD`
- `MQTT_HOST`
- `MQTT_PORT`
- `MQTT_USERNAME`
- `MQTT_PASSWORD`
- `DEVICE_ID`
- `TELEMETRY_INTERVAL_MS`
- `WIFI_RETRY_DELAY_MS`
- `MQTT_RETRY_DELAY_MS`
- `DEBUG_ENABLED`

Replace the credentials before flashing and especially before pushing the project to a public GitHub repository.

## MQTT Topics

- publishes telemetry to `streetlight/<device_id>/telemetry`
- subscribes to `streetlight/<device_id>/command`
- publishes status to `streetlight/<device_id>/status`

## Firmware Lifecycle

### Boot

On startup the sketch:

1. starts the serial port for debugging
2. builds the MQTT topic strings for the current `DEVICE_ID`
3. configures pins and ADC settings
4. applies initial LED states of `on, on, on`
5. configures NTP time sync

### Main Loop

The loop continuously:

1. retries WiFi connection if disconnected
2. retries MQTT connection if WiFi is available but MQTT is disconnected
3. calls `mqttClient.loop()` to process inbound traffic
4. publishes telemetry every `5000` ms

### When MQTT Connects

After a successful broker connection the sketch:

1. subscribes to the device command topic
2. publishes a status message with `status = "online"`
3. publishes an initial telemetry snapshot

### When a Command Arrives

`mqttCallback()` checks whether the topic exactly matches the device command topic. If it does:

1. `handleCommand()` parses the JSON payload
2. the command is ignored if `device_id` does not match this device
3. the sketch reads `led1_expected`, `led2_expected`, and `led3_expected`
4. the LED GPIO outputs are updated immediately
5. a status acknowledgement with `status = "applied"` is published
6. a fresh telemetry payload is sent right away

## Telemetry Payload

Example:

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

Fields:

- `ldr1`, `ldr2`, `ldr3`: analog sensor values
- `led1_working`, `led2_working`, `led3_working`: digital feedback values
- `led1_expected`, `led2_expected`, `led3_expected`: the current command state held by the device
- `ts`: UTC timestamp if NTP time is valid

## Status Payload

Example:

```json
{
  "device_id": "esp32-01",
  "command_id": "manual-1",
  "status": "applied",
  "led1_expected": 1,
  "led2_expected": 0,
  "led3_expected": 1,
  "ts": "2025-04-22T20:00:06Z"
}
```

## Current Behavior Notes

- The sketch stores expected LED states locally in `led1Expected`, `led2Expected`, and `led3Expected`.
- The backend can include `auto_lights_enabled` and `auto_light_threshold` in command payloads, but the current firmware does not use those fields directly.
- Auto-light decisions are made by the backend, which sends normal LED state commands after evaluating ambient light.
- Timestamps are only included after NTP sync becomes valid.

## Flashing

1. Open the sketch in Arduino IDE.
2. Install `PubSubClient` and `ArduinoJson` if needed.
3. Select the correct ESP32 board and serial port.
4. Update WiFi, MQTT, and `DEVICE_ID` constants.
5. Upload the sketch.
6. Open the serial monitor and verify the device connects and begins publishing.

## Serial Debugging

With `DEBUG_ENABLED` set to `true`, the sketch prints:

- WiFi state changes
- MQTT connection state changes
- topic names
- raw inbound commands
- raw outbound telemetry and status payloads
- timestamp availability
- LED state transitions

## Troubleshooting

- If no timestamp appears, verify the device has internet access for NTP.
- If MQTT never connects, verify broker host, port, username, and password.
- If commands are ignored, verify the payload `device_id` matches the sketch `DEVICE_ID`.
- If the backend shows faults unexpectedly, inspect the LED feedback wiring on `GPIO18`, `GPIO19`, and `GPIO23`.

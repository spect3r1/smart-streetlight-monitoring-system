#include <ArduinoJson.h>
#include <PubSubClient.h>
#include <WiFi.h>
#include <time.h>

#define DEBUG_ENABLED true

static const char *WIFI_SSID = "";
static const char *WIFI_PASSWORD = "";

static const char *MQTT_HOST = "104.248.227.238";
static const uint16_t MQTT_PORT = 1883;
static const char *MQTT_USERNAME = "streetlight";
static const char *MQTT_PASSWORD = "y9y2AtrPx2NhMNQKBHYdAR8q";

static const char *DEVICE_ID = "esp32-01";

static const uint8_t LED1_PIN = 25;
static const uint8_t LED2_PIN = 26;
static const uint8_t LED3_PIN = 27;

static const uint8_t LDR1_PIN = 34;
static const uint8_t LDR2_PIN = 35;
static const uint8_t LDR3_PIN = 32;

// New analog ADC1 pins for LED feedback
static const uint8_t LED3_WORKING_PIN = 33;
static const uint8_t LED2_WORKING_PIN = 36;
static const uint8_t LED1_WORKING_PIN = 39;

// 12-bit ADC range = 0 to 4095
// If analogRead(pin) > this value, ledx_working becomes 1.
// Otherwise, ledx_working becomes 0.
static const uint16_t LED_WORKING_THRESHOLD = 60;

static const unsigned long TELEMETRY_INTERVAL_MS = 5000;
static const unsigned long WIFI_RETRY_DELAY_MS = 3000;
static const unsigned long MQTT_RETRY_DELAY_MS = 3000;

WiFiClient wifiClient;
PubSubClient mqttClient(wifiClient);

bool led1Expected = false;
bool led2Expected = false;
bool led3Expected = false;

unsigned long lastTelemetryAt = 0;
unsigned long lastWifiRetryAt = 0;
unsigned long lastMqttRetryAt = 0;

char telemetryTopic[64];
char commandTopic[64];
char statusTopic[64];

int lastWifiStatus = -1;
bool wifiConnectedPrinted = false;
bool mqttConnectedPrinted = false;

void debugLine() {
#if DEBUG_ENABLED
  Serial.println("--------------------------------------------------");
#endif
}

void debugPrintWifiStatus(int status) {
#if DEBUG_ENABLED
  Serial.print("[WiFi] Status code: ");
  Serial.print(status);
  Serial.print(" => ");

  switch (status) {
    case WL_IDLE_STATUS:
      Serial.println("WL_IDLE_STATUS");
      break;
    case WL_NO_SSID_AVAIL:
      Serial.println("WL_NO_SSID_AVAIL");
      break;
    case WL_SCAN_COMPLETED:
      Serial.println("WL_SCAN_COMPLETED");
      break;
    case WL_CONNECTED:
      Serial.println("WL_CONNECTED");
      break;
    case WL_CONNECT_FAILED:
      Serial.println("WL_CONNECT_FAILED");
      break;
    case WL_CONNECTION_LOST:
      Serial.println("WL_CONNECTION_LOST");
      break;
    case WL_DISCONNECTED:
      Serial.println("WL_DISCONNECTED");
      break;
    default:
      Serial.println("UNKNOWN");
      break;
  }
#endif
}

void debugPrintMqttState(int state) {
#if DEBUG_ENABLED
  Serial.print("[MQTT] State code: ");
  Serial.print(state);
  Serial.print(" => ");

  switch (state) {
    case MQTT_CONNECTION_TIMEOUT:
      Serial.println("MQTT_CONNECTION_TIMEOUT");
      break;
    case MQTT_CONNECTION_LOST:
      Serial.println("MQTT_CONNECTION_LOST");
      break;
    case MQTT_CONNECT_FAILED:
      Serial.println("MQTT_CONNECT_FAILED");
      break;
    case MQTT_DISCONNECTED:
      Serial.println("MQTT_DISCONNECTED");
      break;
    case MQTT_CONNECTED:
      Serial.println("MQTT_CONNECTED");
      break;
    case MQTT_CONNECT_BAD_PROTOCOL:
      Serial.println("MQTT_CONNECT_BAD_PROTOCOL");
      break;
    case MQTT_CONNECT_BAD_CLIENT_ID:
      Serial.println("MQTT_CONNECT_BAD_CLIENT_ID");
      break;
    case MQTT_CONNECT_UNAVAILABLE:
      Serial.println("MQTT_CONNECT_UNAVAILABLE");
      break;
    case MQTT_CONNECT_BAD_CREDENTIALS:
      Serial.println("MQTT_CONNECT_BAD_CREDENTIALS");
      break;
    case MQTT_CONNECT_UNAUTHORIZED:
      Serial.println("MQTT_CONNECT_UNAUTHORIZED");
      break;
    default:
      Serial.println("UNKNOWN");
      break;
  }
#endif
}

void printExpectedStates() {
#if DEBUG_ENABLED
  Serial.print("[LED] Expected states => LED1=");
  Serial.print(led1Expected ? "ON" : "OFF");
  Serial.print(", LED2=");
  Serial.print(led2Expected ? "ON" : "OFF");
  Serial.print(", LED3=");
  Serial.println(led3Expected ? "ON" : "OFF");
#endif
}

int readLedWorkingState(uint8_t pin) {
  int rawValue = analogRead(pin);

#if DEBUG_ENABLED
  Serial.print("[LED_FEEDBACK] GPIO");
  Serial.print(pin);
  Serial.print(" analog raw = ");
  Serial.print(rawValue);
  Serial.print(" | threshold = ");
  Serial.print(LED_WORKING_THRESHOLD);
  Serial.print(" | state = ");
  Serial.println(rawValue > LED_WORKING_THRESHOLD ? 1 : 0);
#endif

  return rawValue > LED_WORKING_THRESHOLD ? 1 : 0;
}

void applyExpectedStates(bool led1, bool led2, bool led3) {
#if DEBUG_ENABLED
  Serial.println("[LED] applyExpectedStates() called");
  Serial.print("[LED] New requested states => LED1=");
  Serial.print(led1 ? "ON" : "OFF");
  Serial.print(", LED2=");
  Serial.print(led2 ? "ON" : "OFF");
  Serial.print(", LED3=");
  Serial.println(led3 ? "ON" : "OFF");
#endif

  led1Expected = led1;
  led2Expected = led2;
  led3Expected = led3;

  digitalWrite(LED1_PIN, led1Expected ? HIGH : LOW);
  digitalWrite(LED2_PIN, led2Expected ? HIGH : LOW);
  digitalWrite(LED3_PIN, led3Expected ? HIGH : LOW);

#if DEBUG_ENABLED
  Serial.println("[LED] GPIO states written");

  Serial.print("[LED] GPIO");
  Serial.print(LED1_PIN);
  Serial.print(" = ");
  Serial.println(led1Expected ? "HIGH" : "LOW");

  Serial.print("[LED] GPIO");
  Serial.print(LED2_PIN);
  Serial.print(" = ");
  Serial.println(led2Expected ? "HIGH" : "LOW");

  Serial.print("[LED] GPIO");
  Serial.print(LED3_PIN);
  Serial.print(" = ");
  Serial.println(led3Expected ? "HIGH" : "LOW");
#endif
}

bool hasValidTime() {
  time_t now = time(nullptr);
  bool valid = now > 1700000000;

#if DEBUG_ENABLED
  Serial.print("[TIME] Current Unix time: ");
  Serial.print(now);
  Serial.print(" | Valid: ");
  Serial.println(valid ? "YES" : "NO");
#endif

  return valid;
}

void addTimestamp(JsonDocument &doc) {
#if DEBUG_ENABLED
  Serial.println("[TIME] addTimestamp() called");
#endif

  if (!hasValidTime()) {
#if DEBUG_ENABLED
    Serial.println("[TIME] Time not valid yet, skipping timestamp");
#endif
    return;
  }

  time_t now = time(nullptr);
  struct tm timeInfo;
  gmtime_r(&now, &timeInfo);

  char buffer[32];
  strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%SZ", &timeInfo);
  doc["ts"] = buffer;

#if DEBUG_ENABLED
  Serial.print("[TIME] Timestamp added: ");
  Serial.println(buffer);
#endif
}

void publishStatus(const char *status, const char *commandId = nullptr) {
#if DEBUG_ENABLED
  debugLine();
  Serial.println("[STATUS] publishStatus() called");
  Serial.print("[STATUS] Status: ");
  Serial.println(status);

  if (commandId != nullptr) {
    Serial.print("[STATUS] Command ID: ");
    Serial.println(commandId);
  } else {
    Serial.println("[STATUS] Command ID: nullptr");
  }
#endif

  StaticJsonDocument<320> doc;
  doc["device_id"] = DEVICE_ID;
  doc["status"] = status;
  doc["led1_expected"] = led1Expected ? 1 : 0;
  doc["led2_expected"] = led2Expected ? 1 : 0;
  doc["led3_expected"] = led3Expected ? 1 : 0;

  if (commandId != nullptr && commandId[0] != '\0') {
    doc["command_id"] = commandId;
  }

  addTimestamp(doc);

  char payload[320];
  size_t length = serializeJson(doc, payload, sizeof(payload));

#if DEBUG_ENABLED
  Serial.print("[STATUS] Topic: ");
  Serial.println(statusTopic);

  Serial.print("[STATUS] Payload length: ");
  Serial.println(length);

  Serial.print("[STATUS] Payload: ");
  Serial.println(payload);

  Serial.print("[STATUS] MQTT connected before publish: ");
  Serial.println(mqttClient.connected() ? "YES" : "NO");
#endif

  bool ok = mqttClient.publish(
    statusTopic,
    reinterpret_cast<const uint8_t *>(payload),
    static_cast<unsigned int>(length),
    false
  );

#if DEBUG_ENABLED
  Serial.print("[STATUS] Publish result: ");
  Serial.println(ok ? "SUCCESS" : "FAILED");

  if (!ok) {
    debugPrintMqttState(mqttClient.state());
  }

  debugLine();
#endif
}

void publishTelemetry() {
#if DEBUG_ENABLED
  debugLine();
  Serial.println("[TELEMETRY] publishTelemetry() called");
#endif

  int ldr1 = analogRead(LDR1_PIN);
  int ldr2 = analogRead(LDR2_PIN);
  int ldr3 = analogRead(LDR3_PIN);

  int led1Working = readLedWorkingState(LED1_WORKING_PIN);
  int led2Working = readLedWorkingState(LED2_WORKING_PIN);
  int led3Working = readLedWorkingState(LED3_WORKING_PIN);

#if DEBUG_ENABLED
  Serial.print("[TELEMETRY] LDR1 GPIO");
  Serial.print(LDR1_PIN);
  Serial.print(" = ");
  Serial.println(ldr1);

  Serial.print("[TELEMETRY] LDR2 GPIO");
  Serial.print(LDR2_PIN);
  Serial.print(" = ");
  Serial.println(ldr2);

  Serial.print("[TELEMETRY] LDR3 GPIO");
  Serial.print(LDR3_PIN);
  Serial.print(" = ");
  Serial.println(ldr3);

  Serial.print("[TELEMETRY] LED1 working GPIO");
  Serial.print(LED1_WORKING_PIN);
  Serial.print(" = ");
  Serial.println(led1Working);

  Serial.print("[TELEMETRY] LED2 working GPIO");
  Serial.print(LED2_WORKING_PIN);
  Serial.print(" = ");
  Serial.println(led2Working);

  Serial.print("[TELEMETRY] LED3 working GPIO");
  Serial.print(LED3_WORKING_PIN);
  Serial.print(" = ");
  Serial.println(led3Working);

  printExpectedStates();
#endif

  StaticJsonDocument<384> doc;
  doc["device_id"] = DEVICE_ID;
  doc["ldr1"] = ldr1;
  doc["ldr2"] = ldr2;
  doc["ldr3"] = ldr3;
  doc["led1_working"] = led1Working;
  doc["led2_working"] = led2Working;
  doc["led3_working"] = led3Working;
  doc["led1_expected"] = led1Expected ? 1 : 0;
  doc["led2_expected"] = led2Expected ? 1 : 0;
  doc["led3_expected"] = led3Expected ? 1 : 0;

  addTimestamp(doc);

  char payload[384];
  size_t length = serializeJson(doc, payload, sizeof(payload));

#if DEBUG_ENABLED
  Serial.print("[TELEMETRY] Topic: ");
  Serial.println(telemetryTopic);

  Serial.print("[TELEMETRY] Payload length: ");
  Serial.println(length);

  Serial.print("[TELEMETRY] Payload: ");
  Serial.println(payload);

  Serial.print("[TELEMETRY] MQTT connected before publish: ");
  Serial.println(mqttClient.connected() ? "YES" : "NO");
#endif

  bool ok = mqttClient.publish(
    telemetryTopic,
    reinterpret_cast<const uint8_t *>(payload),
    static_cast<unsigned int>(length),
    false
  );

#if DEBUG_ENABLED
  Serial.print("[TELEMETRY] Publish result: ");
  Serial.println(ok ? "SUCCESS" : "FAILED");

  if (!ok) {
    debugPrintMqttState(mqttClient.state());
  }

  debugLine();
#endif
}

void handleCommand(const byte *payloadBytes, unsigned int length) {
#if DEBUG_ENABLED
  debugLine();
  Serial.println("[COMMAND] handleCommand() called");

  Serial.print("[COMMAND] Payload length: ");
  Serial.println(length);

  Serial.print("[COMMAND] Raw payload: ");
  Serial.write(payloadBytes, length);
  Serial.println();
#endif

  StaticJsonDocument<384> doc;
  DeserializationError error = deserializeJson(doc, payloadBytes, length);

  if (error) {
#if DEBUG_ENABLED
    Serial.print("[COMMAND] JSON parse failed: ");
    Serial.println(error.c_str());
    debugLine();
#endif
    return;
  }

#if DEBUG_ENABLED
  Serial.println("[COMMAND] JSON parsed successfully");

  Serial.print("[COMMAND] Parsed JSON: ");
  serializeJson(doc, Serial);
  Serial.println();
#endif

  const char *targetDevice = doc["device_id"] | DEVICE_ID;

#if DEBUG_ENABLED
  Serial.print("[COMMAND] Target device: ");
  Serial.println(targetDevice);

  Serial.print("[COMMAND] This device: ");
  Serial.println(DEVICE_ID);
#endif

  if (strcmp(targetDevice, DEVICE_ID) != 0) {
#if DEBUG_ENABLED
    Serial.println("[COMMAND] Command ignored because device_id does not match");
    debugLine();
#endif
    return;
  }

#if DEBUG_ENABLED
  Serial.println("[COMMAND] Command is for this device");
#endif

  bool nextLed1 = doc.containsKey("led1_expected") ? (doc["led1_expected"].as<int>() != 0) : led1Expected;
  bool nextLed2 = doc.containsKey("led2_expected") ? (doc["led2_expected"].as<int>() != 0) : led2Expected;
  bool nextLed3 = doc.containsKey("led3_expected") ? (doc["led3_expected"].as<int>() != 0) : led3Expected;

#if DEBUG_ENABLED
  Serial.print("[COMMAND] led1_expected present: ");
  Serial.println(doc.containsKey("led1_expected") ? "YES" : "NO");

  Serial.print("[COMMAND] led2_expected present: ");
  Serial.println(doc.containsKey("led2_expected") ? "YES" : "NO");

  Serial.print("[COMMAND] led3_expected present: ");
  Serial.println(doc.containsKey("led3_expected") ? "YES" : "NO");

  Serial.print("[COMMAND] Next LED1: ");
  Serial.println(nextLed1 ? "ON" : "OFF");

  Serial.print("[COMMAND] Next LED2: ");
  Serial.println(nextLed2 ? "ON" : "OFF");

  Serial.print("[COMMAND] Next LED3: ");
  Serial.println(nextLed3 ? "ON" : "OFF");
#endif

  applyExpectedStates(nextLed1, nextLed2, nextLed3);

  const char *commandId = doc["command_id"] | "";

#if DEBUG_ENABLED
  Serial.print("[COMMAND] command_id: ");
  Serial.println(commandId);
  Serial.println("[COMMAND] Publishing applied status...");
#endif

  publishStatus("applied", commandId);

#if DEBUG_ENABLED
  Serial.println("[COMMAND] Publishing telemetry after command...");
#endif

  publishTelemetry();

#if DEBUG_ENABLED
  Serial.println("[COMMAND] Command handling finished");
  debugLine();
#endif
}

void mqttCallback(char *topic, byte *payload, unsigned int length) {
#if DEBUG_ENABLED
  debugLine();
  Serial.println("[MQTT] mqttCallback() triggered");

  Serial.print("[MQTT] Incoming topic: ");
  Serial.println(topic);

  Serial.print("[MQTT] Expected command topic: ");
  Serial.println(commandTopic);

  Serial.print("[MQTT] Incoming payload length: ");
  Serial.println(length);

  Serial.print("[MQTT] Incoming payload: ");
  Serial.write(payload, length);
  Serial.println();
#endif

  if (strcmp(topic, commandTopic) == 0) {
#if DEBUG_ENABLED
    Serial.println("[MQTT] Topic matches command topic");
#endif
    handleCommand(payload, length);
  } else {
#if DEBUG_ENABLED
    Serial.println("[MQTT] Topic ignored because it does not match command topic");
#endif
  }

#if DEBUG_ENABLED
  debugLine();
#endif
}

void syncClock() {
#if DEBUG_ENABLED
  Serial.println("[TIME] syncClock() called");
  Serial.println("[TIME] NTP servers: pool.ntp.org, time.nist.gov, time.google.com");
#endif

  configTime(0, 0, "pool.ntp.org", "time.nist.gov", "time.google.com");

#if DEBUG_ENABLED
  Serial.println("[TIME] configTime() called. Time may need a few seconds after WiFi connects.");
#endif
}

void connectWifi() {
  int currentStatus = WiFi.status();

  if (currentStatus != lastWifiStatus) {
#if DEBUG_ENABLED
    Serial.println("[WiFi] WiFi status changed");
    debugPrintWifiStatus(currentStatus);
#endif
    lastWifiStatus = currentStatus;
  }

  if (currentStatus == WL_CONNECTED) {
    if (!wifiConnectedPrinted) {
#if DEBUG_ENABLED
      Serial.println("[WiFi] Connected successfully");
      Serial.print("[WiFi] SSID: ");
      Serial.println(WiFi.SSID());

      Serial.print("[WiFi] Local IP: ");
      Serial.println(WiFi.localIP());

      Serial.print("[WiFi] Gateway IP: ");
      Serial.println(WiFi.gatewayIP());

      Serial.print("[WiFi] Subnet mask: ");
      Serial.println(WiFi.subnetMask());

      Serial.print("[WiFi] DNS IP: ");
      Serial.println(WiFi.dnsIP());

      Serial.print("[WiFi] RSSI: ");
      Serial.print(WiFi.RSSI());
      Serial.println(" dBm");
#endif
      wifiConnectedPrinted = true;
    }

    return;
  }

  wifiConnectedPrinted = false;

  unsigned long now = millis();
  if (now - lastWifiRetryAt < WIFI_RETRY_DELAY_MS) {
    return;
  }

  lastWifiRetryAt = now;

#if DEBUG_ENABLED
  debugLine();
  Serial.println("[WiFi] Attempting WiFi connection...");
  Serial.print("[WiFi] SSID: ");
  Serial.println(WIFI_SSID);
  Serial.print("[WiFi] Retry interval ms: ");
  Serial.println(WIFI_RETRY_DELAY_MS);
#endif

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

#if DEBUG_ENABLED
  Serial.println("[WiFi] WiFi.begin() called");
  debugLine();
#endif
}

void connectMqtt() {
  if (WiFi.status() != WL_CONNECTED) {
#if DEBUG_ENABLED
    static unsigned long lastNoWifiPrint = 0;
    unsigned long nowPrint = millis();

    if (nowPrint - lastNoWifiPrint > 5000) {
      lastNoWifiPrint = nowPrint;
      Serial.println("[MQTT] Cannot connect MQTT because WiFi is not connected");
    }
#endif
    return;
  }

  if (mqttClient.connected()) {
    if (!mqttConnectedPrinted) {
#if DEBUG_ENABLED
      Serial.println("[MQTT] Already connected");
#endif
      mqttConnectedPrinted = true;
    }
    return;
  }

  mqttConnectedPrinted = false;

  unsigned long now = millis();
  if (now - lastMqttRetryAt < MQTT_RETRY_DELAY_MS) {
    return;
  }

  lastMqttRetryAt = now;

#if DEBUG_ENABLED
  debugLine();
  Serial.println("[MQTT] Attempting MQTT connection...");
  Serial.print("[MQTT] Host: ");
  Serial.println(MQTT_HOST);
  Serial.print("[MQTT] Port: ");
  Serial.println(MQTT_PORT);
  Serial.print("[MQTT] Username: ");
  Serial.println(MQTT_USERNAME);
#endif

  String clientId = String("streetlight-") + DEVICE_ID;

#if DEBUG_ENABLED
  Serial.print("[MQTT] Client ID: ");
  Serial.println(clientId);
#endif

  if (!mqttClient.connect(clientId.c_str(), MQTT_USERNAME, MQTT_PASSWORD)) {
#if DEBUG_ENABLED
    Serial.println("[MQTT] Connection failed");
    debugPrintMqttState(mqttClient.state());
    debugLine();
#endif
    return;
  }

#if DEBUG_ENABLED
  Serial.println("[MQTT] Connected successfully");
#endif

  bool subscribed = mqttClient.subscribe(commandTopic, 1);

#if DEBUG_ENABLED
  Serial.print("[MQTT] Subscribe topic: ");
  Serial.println(commandTopic);

  Serial.print("[MQTT] Subscribe QoS: ");
  Serial.println(1);

  Serial.print("[MQTT] Subscribe result: ");
  Serial.println(subscribed ? "SUCCESS" : "FAILED");
#endif

  publishStatus("online");
  publishTelemetry();

#if DEBUG_ENABLED
  Serial.println("[MQTT] Initial status and telemetry published");
  debugLine();
#endif
}

void setupPins() {
#if DEBUG_ENABLED
  debugLine();
  Serial.println("[PINS] setupPins() called");

  Serial.print("[PINS] LED1 output pin: GPIO");
  Serial.println(LED1_PIN);

  Serial.print("[PINS] LED2 output pin: GPIO");
  Serial.println(LED2_PIN);

  Serial.print("[PINS] LED3 output pin: GPIO");
  Serial.println(LED3_PIN);

  Serial.print("[PINS] LDR1 analog pin: GPIO");
  Serial.println(LDR1_PIN);

  Serial.print("[PINS] LDR2 analog pin: GPIO");
  Serial.println(LDR2_PIN);

  Serial.print("[PINS] LDR3 analog pin: GPIO");
  Serial.println(LDR3_PIN);

  Serial.print("[PINS] LED1 working analog input pin: GPIO");
  Serial.println(LED1_WORKING_PIN);

  Serial.print("[PINS] LED2 working analog input pin: GPIO");
  Serial.println(LED2_WORKING_PIN);

  Serial.print("[PINS] LED3 working analog input pin: GPIO");
  Serial.println(LED3_WORKING_PIN);

  Serial.print("[PINS] LED working threshold: ");
  Serial.println(LED_WORKING_THRESHOLD);
#endif

  pinMode(LED1_PIN, OUTPUT);
  pinMode(LED2_PIN, OUTPUT);
  pinMode(LED3_PIN, OUTPUT);

  pinMode(LED1_WORKING_PIN, INPUT);
  pinMode(LED2_WORKING_PIN, INPUT);
  pinMode(LED3_WORKING_PIN, INPUT);

#if DEBUG_ENABLED
  Serial.println("[PINS] LED pins configured as OUTPUT");
  Serial.println("[PINS] LED working pins configured as analog INPUT");
#endif

  analogReadResolution(12);

#if DEBUG_ENABLED
  Serial.println("[ADC] analogReadResolution(12) configured");
#endif

  analogSetPinAttenuation(LDR1_PIN, ADC_11db);
  analogSetPinAttenuation(LDR2_PIN, ADC_11db);
  analogSetPinAttenuation(LDR3_PIN, ADC_11db);

  analogSetPinAttenuation(LED1_WORKING_PIN, ADC_11db);
  analogSetPinAttenuation(LED2_WORKING_PIN, ADC_11db);
  analogSetPinAttenuation(LED3_WORKING_PIN, ADC_11db);

#if DEBUG_ENABLED
  Serial.println("[ADC] ADC attenuation set to ADC_11db for LDR and LED working pins");
  Serial.println("[PINS] Applying initial LED states...");
#endif

  applyExpectedStates(true, true, true);

#if DEBUG_ENABLED
  Serial.println("[PINS] setupPins() finished");
  debugLine();
#endif
}

void setupTopics() {
#if DEBUG_ENABLED
  debugLine();
  Serial.println("[TOPICS] setupTopics() called");
#endif

  snprintf(telemetryTopic, sizeof(telemetryTopic), "streetlight/%s/telemetry", DEVICE_ID);
  snprintf(commandTopic, sizeof(commandTopic), "streetlight/%s/command", DEVICE_ID);
  snprintf(statusTopic, sizeof(statusTopic), "streetlight/%s/status", DEVICE_ID);

#if DEBUG_ENABLED
  Serial.print("[TOPICS] telemetryTopic: ");
  Serial.println(telemetryTopic);

  Serial.print("[TOPICS] commandTopic: ");
  Serial.println(commandTopic);

  Serial.print("[TOPICS] statusTopic: ");
  Serial.println(statusTopic);

  Serial.println("[TOPICS] setupTopics() finished");
  debugLine();
#endif
}

void setup() {
  Serial.begin(115200);
  delay(1000);

#if DEBUG_ENABLED
  Serial.println();
  debugLine();
  Serial.println("[BOOT] ESP32 streetlight controller starting...");
  Serial.print("[BOOT] Device ID: ");
  Serial.println(DEVICE_ID);

  Serial.print("[BOOT] CPU frequency MHz: ");
  Serial.println(getCpuFrequencyMhz());

  Serial.print("[BOOT] Free heap: ");
  Serial.println(ESP.getFreeHeap());

  Serial.print("[BOOT] Flash chip size: ");
  Serial.println(ESP.getFlashChipSize());

  Serial.print("[BOOT] SDK version: ");
  Serial.println(ESP.getSdkVersion());
  debugLine();
#endif

  setupPins();
  setupTopics();
  syncClock();

#if DEBUG_ENABLED
  debugLine();
  Serial.println("[MQTT] Configuring MQTT client...");
  Serial.print("[MQTT] Server: ");
  Serial.print(MQTT_HOST);
  Serial.print(":");
  Serial.println(MQTT_PORT);
#endif

  mqttClient.setServer(MQTT_HOST, MQTT_PORT);
  mqttClient.setCallback(mqttCallback);
  mqttClient.setBufferSize(512);

#if DEBUG_ENABLED
  Serial.println("[MQTT] MQTT server configured");
  Serial.println("[MQTT] MQTT callback configured");
  Serial.println("[MQTT] MQTT buffer size set to 512");

  Serial.println("[BOOT] Setup complete. Entering loop...");
  debugLine();
#endif
}

void loop() {
  connectWifi();

  if (WiFi.status() == WL_CONNECTED) {
    connectMqtt();
  }

  if (mqttClient.connected()) {
    mqttClient.loop();

    unsigned long now = millis();
    if (now - lastTelemetryAt >= TELEMETRY_INTERVAL_MS) {
      lastTelemetryAt = now;

#if DEBUG_ENABLED
      Serial.println("[LOOP] Telemetry interval reached");
#endif

      publishTelemetry();
    }
  } else {
#if DEBUG_ENABLED
    static unsigned long lastMqttDisconnectedPrint = 0;
    unsigned long nowPrint = millis();

    if (WiFi.status() == WL_CONNECTED && nowPrint - lastMqttDisconnectedPrint > 5000) {
      lastMqttDisconnectedPrint = nowPrint;
      Serial.println("[LOOP] WiFi connected but MQTT is not connected yet");
      debugPrintMqttState(mqttClient.state());
    }
#endif
  }
}

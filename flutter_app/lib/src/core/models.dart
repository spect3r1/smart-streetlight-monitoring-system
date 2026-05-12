class UserSession {
  const UserSession({
    required this.token,
    required this.expiresIn,
    required this.username,
  });

  final String token;
  final int expiresIn;
  final String username;
}

class DashboardSummary {
  const DashboardSummary({
    required this.totalDevices,
    required this.onlineDevices,
    required this.devicesWithFaults,
    required this.telemetryEventsLast24h,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      totalDevices: _asInt(json['total_devices']) ?? 0,
      onlineDevices: _asInt(json['online_devices']) ?? 0,
      devicesWithFaults: _asInt(json['devices_with_faults']) ?? 0,
      telemetryEventsLast24h: _asInt(json['telemetry_events_last_24h']) ?? 0,
    );
  }

  final int totalDevices;
  final int onlineDevices;
  final int devicesWithFaults;
  final int telemetryEventsLast24h;
}

class DeviceSummary {
  const DeviceSummary({
    required this.id,
    required this.name,
    required this.lastSeenAt,
    required this.lastPeriod,
    required this.ambientValue,
    required this.ambientSource,
    required this.hasFault,
    required this.led1Reading,
    required this.led2Reading,
    required this.led3Reading,
    required this.led1Working,
    required this.led2Working,
    required this.led3Working,
    required this.led1Expected,
    required this.led2Expected,
    required this.led3Expected,
    required this.autoLightsEnabled,
    required this.autoLightThreshold,
    required this.lastCommandAt,
    required this.createdAt,
  });

  factory DeviceSummary.fromJson(Map<String, dynamic> json) {
    return DeviceSummary(
      id: json['id'] as String? ?? 'unknown-device',
      name: json['name'] as String?,
      lastSeenAt: _parseDate(json['last_seen_at']),
      lastPeriod: json['last_period'] as String?,
      ambientValue: _asInt(json['ambient_value']),
      ambientSource: json['ambient_source'] as String?,
      hasFault: _asBool(json['has_fault']) ?? false,
      led1Reading: _asInt(json['led1_reading']),
      led2Reading: _asInt(json['led2_reading']),
      led3Reading: _asInt(json['led3_reading']),
      led1Working: _asBool(json['led1_working']),
      led2Working: _asBool(json['led2_working']),
      led3Working: _asBool(json['led3_working']),
      led1Expected: _asBool(json['led1_expected']),
      led2Expected: _asBool(json['led2_expected']),
      led3Expected: _asBool(json['led3_expected']),
      autoLightsEnabled: _asBool(json['auto_lights_enabled']) ?? false,
      autoLightThreshold: _asInt(json['auto_light_threshold']),
      lastCommandAt: _parseDate(json['last_command_at']),
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
    );
  }

  final String id;
  final String? name;
  final DateTime? lastSeenAt;
  final String? lastPeriod;
  final int? ambientValue;
  final String? ambientSource;
  final bool hasFault;
  final int? led1Reading;
  final int? led2Reading;
  final int? led3Reading;
  final bool? led1Working;
  final bool? led2Working;
  final bool? led3Working;
  final bool? led1Expected;
  final bool? led2Expected;
  final bool? led3Expected;
  final bool autoLightsEnabled;
  final int? autoLightThreshold;
  final DateTime? lastCommandAt;
  final DateTime createdAt;

  String get displayName => (name == null || name!.trim().isEmpty) ? id : name!;
}

class DeviceDetail extends DeviceSummary {
  const DeviceDetail({
    required super.id,
    required super.name,
    required super.lastSeenAt,
    required super.lastPeriod,
    required super.ambientValue,
    required super.ambientSource,
    required super.hasFault,
    required super.led1Reading,
    required super.led2Reading,
    required super.led3Reading,
    required super.led1Working,
    required super.led2Working,
    required super.led3Working,
    required super.led1Expected,
    required super.led2Expected,
    required super.led3Expected,
    required super.autoLightsEnabled,
    required super.autoLightThreshold,
    required super.lastCommandAt,
    required super.createdAt,
    required this.lastTelemetryPayload,
    required this.lastStatusPayload,
    required this.lastFaultPayload,
  });

  factory DeviceDetail.fromJson(Map<String, dynamic> json) {
    final summary = DeviceSummary.fromJson(json);
    return DeviceDetail(
      id: summary.id,
      name: summary.name,
      lastSeenAt: summary.lastSeenAt,
      lastPeriod: summary.lastPeriod,
      ambientValue: summary.ambientValue,
      ambientSource: summary.ambientSource,
      hasFault: summary.hasFault,
      led1Reading: summary.led1Reading,
      led2Reading: summary.led2Reading,
      led3Reading: summary.led3Reading,
      led1Working: summary.led1Working,
      led2Working: summary.led2Working,
      led3Working: summary.led3Working,
      led1Expected: summary.led1Expected,
      led2Expected: summary.led2Expected,
      led3Expected: summary.led3Expected,
      autoLightsEnabled: summary.autoLightsEnabled,
      autoLightThreshold: summary.autoLightThreshold,
      lastCommandAt: summary.lastCommandAt,
      createdAt: summary.createdAt,
      lastTelemetryPayload: _asStringMap(json['last_telemetry_payload']),
      lastStatusPayload: _asStringMap(json['last_status_payload']),
      lastFaultPayload: _asStringMap(json['last_fault_payload']),
    );
  }

  final Map<String, dynamic>? lastTelemetryPayload;
  final Map<String, dynamic>? lastStatusPayload;
  final Map<String, dynamic>? lastFaultPayload;
}

class TelemetryEntry {
  const TelemetryEntry({
    required this.id,
    required this.deviceId,
    required this.ambientLdr,
    required this.ldr1,
    required this.ldr2,
    required this.ldr3,
    required this.led1Working,
    required this.led2Working,
    required this.led3Working,
    required this.led1Expected,
    required this.led2Expected,
    required this.led3Expected,
    required this.rawPayload,
    required this.receivedAt,
  });

  factory TelemetryEntry.fromJson(Map<String, dynamic> json) {
    return TelemetryEntry(
      id: _asInt(json['id']) ?? 0,
      deviceId: json['device_id'] as String? ?? 'unknown-device',
      ambientLdr: _asInt(json['ambient_ldr']),
      ldr1: _asInt(json['ldr1']),
      ldr2: _asInt(json['ldr2']),
      ldr3: _asInt(json['ldr3']),
      led1Working: _asBool(json['led1_working']),
      led2Working: _asBool(json['led2_working']),
      led3Working: _asBool(json['led3_working']),
      led1Expected: _asBool(json['led1_expected']),
      led2Expected: _asBool(json['led2_expected']),
      led3Expected: _asBool(json['led3_expected']),
      rawPayload: _asStringMap(json['raw_payload']) ?? const {},
      receivedAt: _parseDate(json['received_at']) ?? DateTime.now(),
    );
  }

  final int id;
  final String deviceId;
  final int? ambientLdr;
  final int? ldr1;
  final int? ldr2;
  final int? ldr3;
  final bool? led1Working;
  final bool? led2Working;
  final bool? led3Working;
  final bool? led1Expected;
  final bool? led2Expected;
  final bool? led3Expected;
  final Map<String, dynamic> rawPayload;
  final DateTime receivedAt;
}

class StatusEntry {
  const StatusEntry({
    required this.id,
    required this.deviceId,
    required this.sourceTopic,
    required this.period,
    required this.ambientValue,
    required this.ambientSource,
    required this.rawPayload,
    required this.receivedAt,
  });

  factory StatusEntry.fromJson(Map<String, dynamic> json) {
    return StatusEntry(
      id: _asInt(json['id']) ?? 0,
      deviceId: json['device_id'] as String? ?? 'unknown-device',
      sourceTopic: json['source_topic'] as String? ?? '',
      period: json['period'] as String?,
      ambientValue: _asInt(json['ambient_value']),
      ambientSource: json['ambient_source'] as String?,
      rawPayload: _asStringMap(json['raw_payload']) ?? const {},
      receivedAt: _parseDate(json['received_at']) ?? DateTime.now(),
    );
  }

  final int id;
  final String deviceId;
  final String sourceTopic;
  final String? period;
  final int? ambientValue;
  final String? ambientSource;
  final Map<String, dynamic> rawPayload;
  final DateTime receivedAt;

  String get statusLabel {
    final value = rawPayload['status'];
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    return 'acknowledged';
  }

  String? get commandId {
    final value = rawPayload['command_id'];
    return value is String && value.trim().isNotEmpty ? value : null;
  }
}

class FaultyLed {
  const FaultyLed({
    required this.channel,
    required this.reason,
    required this.reading,
    required this.working,
    required this.expected,
  });

  factory FaultyLed.fromJson(Map<String, dynamic> json) {
    return FaultyLed(
      channel: json['channel'] as String? ?? 'unknown',
      reason: json['reason'] as String? ?? 'unknown',
      reading: _asInt(json['reading']),
      working: _asBool(json['working']),
      expected: _asBool(json['expected']),
    );
  }

  final String channel;
  final String reason;
  final int? reading;
  final bool? working;
  final bool? expected;
}

class FaultEntry {
  const FaultEntry({
    required this.id,
    required this.deviceId,
    required this.hasFault,
    required this.faultyLeds,
    required this.rawPayload,
    required this.receivedAt,
  });

  factory FaultEntry.fromJson(Map<String, dynamic> json) {
    return FaultEntry(
      id: _asInt(json['id']) ?? 0,
      deviceId: json['device_id'] as String? ?? 'unknown-device',
      hasFault: _asBool(json['has_fault']) ?? false,
      faultyLeds:
          _asListOfMaps(json['faulty_leds']).map(FaultyLed.fromJson).toList(),
      rawPayload: _asStringMap(json['raw_payload']) ?? const {},
      receivedAt: _parseDate(json['received_at']) ?? DateTime.now(),
    );
  }

  final int id;
  final String deviceId;
  final bool hasFault;
  final List<FaultyLed> faultyLeds;
  final Map<String, dynamic> rawPayload;
  final DateTime receivedAt;
}

class CommandEntry {
  const CommandEntry({
    required this.id,
    required this.commandId,
    required this.deviceId,
    required this.sourceTopic,
    required this.commandName,
    required this.requestedBy,
    required this.status,
    required this.rawPayload,
    required this.responsePayload,
    required this.note,
    required this.createdAt,
    required this.acknowledgedAt,
  });

  factory CommandEntry.fromJson(Map<String, dynamic> json) {
    return CommandEntry(
      id: _asInt(json['id']) ?? 0,
      commandId: json['command_id'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? 'unknown-device',
      sourceTopic: json['source_topic'] as String? ?? '',
      commandName: json['command_name'] as String? ?? 'device_command',
      requestedBy: json['requested_by'] as String? ?? 'unknown',
      status: json['status'] as String? ?? 'queued',
      rawPayload: _asStringMap(json['raw_payload']) ?? const {},
      responsePayload: _asStringMap(json['response_payload']),
      note: json['note'] as String?,
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      acknowledgedAt: _parseDate(json['acknowledged_at']),
    );
  }

  final int id;
  final String commandId;
  final String deviceId;
  final String sourceTopic;
  final String commandName;
  final String requestedBy;
  final String status;
  final Map<String, dynamic> rawPayload;
  final Map<String, dynamic>? responsePayload;
  final String? note;
  final DateTime createdAt;
  final DateTime? acknowledgedAt;
}

class RealtimeEnvelope {
  const RealtimeEnvelope({
    required this.type,
    required this.deviceId,
    required this.payload,
    required this.timestamp,
  });

  factory RealtimeEnvelope.fromJson(Map<String, dynamic> json) {
    return RealtimeEnvelope(
      type: json['type'] as String? ?? 'unknown',
      deviceId: json['device_id'] as String?,
      payload: _asStringMap(json['payload']) ?? const {},
      timestamp: _parseDate(json['timestamp']) ?? DateTime.now(),
    );
  }

  final String type;
  final String? deviceId;
  final Map<String, dynamic> payload;
  final DateTime timestamp;
}

DateTime? _parseDate(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

bool? _asBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'on') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'off') {
      return false;
    }
  }
  return null;
}

Map<String, dynamic>? _asStringMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, entry) => MapEntry(key.toString(), entry),
    );
  }
  return null;
}

List<Map<String, dynamic>> _asListOfMaps(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value
      .whereType<Map>()
      .map((entry) => entry.map((key, item) => MapEntry(key.toString(), item)))
      .toList();
}

import 'package:flutter_test/flutter_test.dart';
import 'package:streetlight_app/src/core/models.dart';

void main() {
  test('dashboard summary parses backend-new fields', () {
    final summary = DashboardSummary.fromJson(const {
      'total_devices': 12,
      'online_devices': 9,
      'devices_with_faults': 2,
      'telemetry_events_last_24h': 188,
    });

    expect(summary.totalDevices, 12);
    expect(summary.onlineDevices, 9);
    expect(summary.devicesWithFaults, 2);
    expect(summary.telemetryEventsLast24h, 188);
  });

  test('device summary parses auto-light and led status fields', () {
    final device = DeviceSummary.fromJson(const {
      'id': 'esp32-01',
      'name': 'Pole A1',
      'has_fault': false,
      'auto_lights_enabled': true,
      'auto_light_threshold': 1750,
      'led1_expected': true,
      'led1_working': true,
      'created_at': '2025-05-01T12:00:00Z',
    });

    expect(device.displayName, 'Pole A1');
    expect(device.autoLightsEnabled, isTrue);
    expect(device.autoLightThreshold, 1750);
    expect(device.led1Expected, isTrue);
    expect(device.led1Working, isTrue);
  });
}

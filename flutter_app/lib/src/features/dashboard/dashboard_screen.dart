import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/app_config.dart';
import '../../core/models.dart';
import '../../core/realtime_service.dart';
import '../../shared/widgets/metric_card.dart';
import '../../shared/widgets/panel_card.dart';
import '../../shared/widgets/status_badge.dart';
import '../auth/auth_controller.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardSummary? _summary;
  List<DeviceSummary> _devices = const [];
  StreamSubscription<RealtimeEnvelope>? _subscription;
  bool _isLoading = true;
  bool _refreshQueued = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _subscription =
        context.read<RealtimeService>().stream.listen(_handleRealtime);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final apiClient = context.read<ApiClient>();
      final results = await Future.wait<dynamic>([
        apiClient.fetchDashboardSummary(),
        apiClient.fetchDevices(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _summary = results[0] as DashboardSummary;
        _devices = results[1] as List<DeviceSummary>;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleRealtime(RealtimeEnvelope event) {
    if (!event.type.startsWith('device.')) {
      return;
    }
    if (_refreshQueued) {
      return;
    }
    _refreshQueued = true;
    Future<void>.delayed(const Duration(milliseconds: 500), () async {
      _refreshQueued = false;
      if (mounted) {
        await _load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final realtime = context.read<RealtimeService>();
    final theme = Theme.of(context);
    final summary = _summary;
    final healthyDevices = _devices.where((device) => !device.hasFault).length;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF4D6), Color(0xFFF6EFE4)],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _ErrorState(message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isWide = constraints.maxWidth >= 920;
                              return Flex(
                                direction:
                                    isWide ? Axis.horizontal : Axis.vertical,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 8,
                                    child: _HeroPanel(
                                      username:
                                          auth.session?.username ?? 'operator',
                                      fleetCount: _devices.length,
                                      healthyDevices: healthyDevices,
                                    ),
                                  ),
                                  SizedBox(
                                    width: isWide ? 16 : 0,
                                    height: isWide ? 0 : 16,
                                  ),
                                  Expanded(
                                    flex: 4,
                                    child: PanelCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                'Session',
                                                style:
                                                    theme.textTheme.titleLarge,
                                              ),
                                              const Spacer(),
                                              ValueListenableBuilder<
                                                  ConnectionStatus>(
                                                valueListenable:
                                                    realtime.connectionState,
                                                builder: (context, state, _) {
                                                  return StatusBadge(
                                                    label:
                                                        _connectionLabel(state),
                                                    color:
                                                        _connectionColor(state),
                                                    compact: true,
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 14),
                                          Text(
                                            'Backend: ${AppConfig.apiBaseUri.host}:${AppConfig.apiBaseUri.port}',
                                            style: theme.textTheme.bodyLarge,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Pull to refresh, or wait for realtime MQTT-backed updates through the WebSocket stream.',
                                            style: theme.textTheme.bodyMedium,
                                          ),
                                          const SizedBox(height: 18),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  onPressed: _load,
                                                  icon:
                                                      const Icon(Icons.refresh),
                                                  label: const Text('Refresh'),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: FilledButton.icon(
                                                  onPressed: auth.logout,
                                                  icon:
                                                      const Icon(Icons.logout),
                                                  label: const Text('Sign out'),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final columns = constraints.maxWidth >= 1080
                                  ? 4
                                  : constraints.maxWidth >= 720
                                      ? 2
                                      : 1;
                              const spacing = 14.0;
                              final itemWidth = (constraints.maxWidth -
                                      (spacing * (columns - 1))) /
                                  columns;

                              final cards = [
                                MetricCard(
                                  label: 'Registered nodes',
                                  value: '${summary?.totalDevices ?? 0}',
                                  caption: 'Devices known by the backend',
                                  tint: const Color(0xFF0A7F6F),
                                  trailing: const Icon(Icons.hub_rounded),
                                ),
                                MetricCard(
                                  label: 'Reporting now',
                                  value: '${summary?.onlineDevices ?? 0}',
                                  caption:
                                      'Recent telemetry or status activity',
                                  tint: const Color(0xFFF28C28),
                                  trailing:
                                      const Icon(Icons.wifi_tethering_rounded),
                                ),
                                MetricCard(
                                  label: 'Fault attention',
                                  value: '${summary?.devicesWithFaults ?? 0}',
                                  caption:
                                      'Nodes with expected-vs-working mismatch',
                                  tint: const Color(0xFFD64545),
                                  trailing:
                                      const Icon(Icons.warning_amber_rounded),
                                ),
                                MetricCard(
                                  label: 'Telemetry / 24h',
                                  value:
                                      '${summary?.telemetryEventsLast24h ?? 0}',
                                  caption:
                                      'MQTT telemetry stored in the last day',
                                  tint: const Color(0xFF18486B),
                                  trailing:
                                      const Icon(Icons.query_stats_rounded),
                                ),
                              ];

                              return Wrap(
                                spacing: spacing,
                                runSpacing: spacing,
                                children: cards
                                    .map(
                                      (card) => SizedBox(
                                          width: itemWidth, child: card),
                                    )
                                    .toList(),
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Fleet overview',
                                  style: theme.textTheme.headlineSmall,
                                ),
                              ),
                              Text(
                                '${_devices.length} devices',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_devices.isEmpty)
                            PanelCard(
                              child: Text(
                                'No devices have reported telemetry yet. Power up an ESP32 node and confirm it publishes to the new MQTT topics.',
                                style: theme.textTheme.bodyLarge,
                              ),
                            )
                          else
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final columns = constraints.maxWidth >= 1160
                                    ? 3
                                    : constraints.maxWidth >= 760
                                        ? 2
                                        : 1;
                                const spacing = 14.0;
                                final itemWidth = (constraints.maxWidth -
                                        (spacing * (columns - 1))) /
                                    columns;
                                return Wrap(
                                  spacing: spacing,
                                  runSpacing: spacing,
                                  children: _devices
                                      .map(
                                        (device) => SizedBox(
                                          width: itemWidth,
                                          child: _DeviceCard(device: device),
                                        ),
                                      )
                                      .toList(),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.username,
    required this.fleetCount,
    required this.healthyDevices,
  });

  final String username;
  final int fleetCount;
  final int healthyDevices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF11203B), Color(0xFF15395C), Color(0xFF0A7F6F)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Operator: $username',
              style: theme.textTheme.labelLarge?.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Streetlight network command center',
            style:
                theme.textTheme.headlineMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            'Track telemetry, watch fault acknowledgements, and drive the new ESP32 command flow from one consistent control surface.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _HeroStat(label: 'Fleet', value: '$fleetCount'),
              _HeroStat(label: 'Healthy', value: '$healthyDevices'),
              _HeroStat(
                label: 'Coverage',
                value: fleetCount == 0
                    ? '0%'
                    : '${((healthyDevices / fleetCount) * 100).round()}%',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Colors.white.withValues(alpha: 0.75)),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});

  final DeviceSummary device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatter = DateFormat('MMM d, HH:mm');
    final isOnline = _isDeviceOnline(device.lastSeenAt);
    final lastSeen = device.lastSeenAt == null
        ? 'No reports yet'
        : formatter.format(device.lastSeenAt!);

    return InkWell(
      onTap: () => context.push('/devices/${device.id}'),
      borderRadius: BorderRadius.circular(28),
      child: PanelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    device.displayName,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                StatusBadge(
                  label: device.hasFault ? 'Fault' : 'Healthy',
                  color: device.hasFault
                      ? const Color(0xFFD64545)
                      : const Color(0xFF0A7F6F),
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusBadge(
                  label: isOnline ? 'Online' : 'Idle',
                  color: isOnline
                      ? const Color(0xFF0A7F6F)
                      : const Color(0xFF6B7280),
                  compact: true,
                ),
                Chip(
                  label: Text(device.lastPeriod ?? 'Period unknown'),
                ),
                if (device.autoLightsEnabled)
                  Chip(
                    label: Text(
                      'Auto ${device.autoLightThreshold ?? '--'}',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _InfoLine(
              label: 'Ambient',
              value: device.ambientValue == null
                  ? '--'
                  : '${device.ambientValue} (${device.ambientSource ?? 'derived'})',
            ),
            _InfoLine(label: 'Last seen', value: lastSeen),
            _InfoLine(
              label: 'Last command',
              value: device.lastCommandAt == null
                  ? 'No command yet'
                  : formatter.format(device.lastCommandAt!),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _LedSnapshot(
                    label: 'L1',
                    reading: device.led1Reading,
                    working: device.led1Working,
                    expected: device.led1Expected,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _LedSnapshot(
                    label: 'L2',
                    reading: device.led2Reading,
                    working: device.led2Working,
                    expected: device.led2Expected,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _LedSnapshot(
                    label: 'L3',
                    reading: device.led3Reading,
                    working: device.led3Working,
                    expected: device.led3Expected,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LedSnapshot extends StatelessWidget {
  const _LedSnapshot({
    required this.label,
    required this.reading,
    required this.working,
    required this.expected,
  });

  final String label;
  final int? reading;
  final bool? working;
  final bool? expected;

  @override
  Widget build(BuildContext context) {
    final tint = (expected == true && working == false)
        ? const Color(0xFFD64545)
        : const Color(0xFF18486B);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(
            '${reading ?? '--'}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'Exp ${_boolLabel(expected)} / Work ${_boolLabel(working)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: theme.textTheme.labelLarge),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: PanelCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 44),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isDeviceOnline(DateTime? lastSeenAt) {
  if (lastSeenAt == null) {
    return false;
  }
  return DateTime.now().difference(lastSeenAt) <= const Duration(minutes: 10);
}

String _boolLabel(bool? value) {
  if (value == null) {
    return '--';
  }
  return value ? 'ON' : 'OFF';
}

String _connectionLabel(ConnectionStatus state) {
  switch (state) {
    case ConnectionStatus.idle:
      return 'Idle';
    case ConnectionStatus.connecting:
      return 'Connecting';
    case ConnectionStatus.connected:
      return 'Live';
    case ConnectionStatus.reconnecting:
      return 'Reconnecting';
    case ConnectionStatus.disconnected:
      return 'Disconnected';
  }
}

Color _connectionColor(ConnectionStatus state) {
  switch (state) {
    case ConnectionStatus.connected:
      return const Color(0xFF0A7F6F);
    case ConnectionStatus.reconnecting:
    case ConnectionStatus.connecting:
      return const Color(0xFFF28C28);
    case ConnectionStatus.idle:
    case ConnectionStatus.disconnected:
      return const Color(0xFF6B7280);
  }
}

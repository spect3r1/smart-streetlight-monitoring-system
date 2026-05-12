import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/realtime_service.dart';
import '../../shared/widgets/panel_card.dart';
import '../../shared/widgets/status_badge.dart';

class DeviceDetailScreen extends StatefulWidget {
  const DeviceDetailScreen({
    super.key,
    required this.deviceId,
  });

  final String deviceId;

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  final _noteController = TextEditingController();

  DeviceDetail? _device;
  List<TelemetryEntry> _telemetry = const [];
  List<StatusEntry> _statuses = const [];
  List<FaultEntry> _faults = const [];
  List<CommandEntry> _commands = const [];
  StreamSubscription<RealtimeEnvelope>? _subscription;

  bool _isLoading = true;
  bool _isSending = false;
  bool _autoLightsEnabled = false;
  double _autoLightThreshold = 1800;
  bool _led1 = false;
  bool _led2 = false;
  bool _led3 = false;
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
    _noteController.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = context.read<ApiClient>();
      final responses = await Future.wait<dynamic>([
        api.fetchDevice(widget.deviceId),
        api.fetchTelemetry(widget.deviceId),
        api.fetchStatuses(widget.deviceId),
        api.fetchFaults(widget.deviceId),
        api.fetchCommands(widget.deviceId),
      ]);
      if (!mounted) {
        return;
      }

      final detail = responses[0] as DeviceDetail;
      setState(() {
        _device = detail;
        _telemetry = responses[1] as List<TelemetryEntry>;
        _statuses = responses[2] as List<StatusEntry>;
        _faults = responses[3] as List<FaultEntry>;
        _commands = responses[4] as List<CommandEntry>;
        _autoLightsEnabled = detail.autoLightsEnabled;
        _autoLightThreshold =
            ((detail.autoLightThreshold ?? _derivedThreshold(detail))
                    .toDouble()
                    .clamp(0, 4095))
                .toDouble();
        _led1 = detail.led1Expected ?? false;
        _led2 = detail.led2Expected ?? false;
        _led3 = detail.led3Expected ?? false;
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
    if (event.deviceId != widget.deviceId) {
      return;
    }
    if (_refreshQueued) {
      return;
    }
    _refreshQueued = true;
    Future<void>.delayed(const Duration(milliseconds: 450), () async {
      _refreshQueued = false;
      if (mounted) {
        await _load();
      }
    });
  }

  int _derivedThreshold(DeviceDetail detail) {
    final values = [
      detail.ambientValue,
      detail.led1Reading,
      detail.led2Reading,
      detail.led3Reading,
    ].whereType<int>().toList();
    if (values.isEmpty) {
      return 1800;
    }
    return values.reduce((left, right) => left + right) ~/ values.length;
  }

  Future<void> _sendCommand() async {
    FocusScope.of(context).unfocus();
    setState(() => _isSending = true);
    try {
      final payload = <String, dynamic>{
        'led1_expected': _led1,
        'led2_expected': _led2,
        'led3_expected': _led3,
        'auto_lights_enabled': _autoLightsEnabled,
        'auto_light_threshold': _autoLightThreshold.round(),
      };
      final note = _noteController.text.trim();
      if (note.isNotEmpty) {
        payload['note'] = note;
      }

      await context.read<ApiClient>().sendCommand(widget.deviceId, payload);
      if (!mounted) {
        return;
      }
      _noteController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Command queued for MQTT delivery.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = _device;
    final theme = Theme.of(context);
    final formatter = DateFormat('MMM d, HH:mm');
    final latestStatus = _statuses.isEmpty ? null : _statuses.first;
    final latestCommand = _commands.isEmpty ? null : _commands.first;
    final latestFault = _faults.isEmpty ? null : _faults.first;
    final isOnline = _isDeviceOnline(device?.lastSeenAt);

    return Scaffold(
      appBar: AppBar(
        title: Text(device?.displayName ?? widget.deviceId),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE7F4F0), Color(0xFFF7F0E5)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _DetailError(message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 40),
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isWide = constraints.maxWidth >= 980;
                              return Flex(
                                direction:
                                    isWide ? Axis.horizontal : Axis.vertical,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 7,
                                    child: _DeviceHero(
                                      device: device,
                                      isOnline: isOnline,
                                      latestStatus: latestStatus,
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
                                          Text(
                                            'Latest command',
                                            style: theme.textTheme.titleLarge,
                                          ),
                                          const SizedBox(height: 12),
                                          if (latestCommand == null)
                                            Text(
                                              'No command has been sent to this node yet.',
                                              style: theme.textTheme.bodyMedium,
                                            )
                                          else ...[
                                            StatusBadge(
                                              label: latestCommand.status,
                                              color: _commandColor(
                                                  latestCommand.status),
                                              compact: true,
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              latestCommand.commandId,
                                              style: theme.textTheme.bodyLarge,
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              'Sent ${formatter.format(latestCommand.createdAt)} by ${latestCommand.requestedBy}',
                                              style: theme.textTheme.bodyMedium,
                                            ),
                                            if (latestCommand.acknowledgedAt !=
                                                null) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                'Acknowledged ${formatter.format(latestCommand.acknowledgedAt!)}',
                                                style:
                                                    theme.textTheme.bodyMedium,
                                              ),
                                            ],
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 18),
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
                                _InfoMetric(
                                  title: 'Last seen',
                                  value: device?.lastSeenAt == null
                                      ? 'No data'
                                      : formatter.format(device!.lastSeenAt!),
                                  caption: 'Most recent MQTT event',
                                ),
                                _InfoMetric(
                                  title: 'Ambient',
                                  value: '${device?.ambientValue ?? '--'}',
                                  caption: device?.ambientSource ??
                                      'No ambient source',
                                ),
                                _InfoMetric(
                                  title: 'Period',
                                  value: device?.lastPeriod ?? 'Unknown',
                                  caption:
                                      'Latest backend period classification',
                                ),
                                _InfoMetric(
                                  title: 'Fault state',
                                  value: device?.hasFault == true
                                      ? 'Attention'
                                      : 'Clear',
                                  caption: latestFault?.faultyLeds.isNotEmpty ==
                                          true
                                      ? '${latestFault!.faultyLeds.length} faulty channel(s)'
                                      : 'No active faulty LED details',
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
                          Text(
                            'Control profile',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          PanelCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'This command form matches the new backend contract and the current ESP32 firmware. It only sends expected LED states plus auto-light settings.',
                                  style: theme.textTheme.bodyLarge,
                                ),
                                const SizedBox(height: 18),
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                      'Enable automatic light policy'),
                                  subtitle: Text(
                                    'Backend will compare ambient values against the configured threshold.',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  value: _autoLightsEnabled,
                                  onChanged: _isSending
                                      ? null
                                      : (value) {
                                          setState(
                                              () => _autoLightsEnabled = value);
                                        },
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Auto-light threshold',
                                  style: theme.textTheme.titleMedium,
                                ),
                                Slider(
                                  value: _autoLightThreshold,
                                  min: 0,
                                  max: 4095,
                                  divisions: 64,
                                  label: _autoLightThreshold.round().toString(),
                                  onChanged: _isSending
                                      ? null
                                      : (value) {
                                          setState(() =>
                                              _autoLightThreshold = value);
                                        },
                                ),
                                Text(
                                  'Threshold: ${_autoLightThreshold.round()}',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  'Expected LED states',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    _ExpectedSwitch(
                                      label: 'LED 1',
                                      value: _led1,
                                      enabled: !_isSending,
                                      onChanged: (value) =>
                                          setState(() => _led1 = value),
                                    ),
                                    _ExpectedSwitch(
                                      label: 'LED 2',
                                      value: _led2,
                                      enabled: !_isSending,
                                      onChanged: (value) =>
                                          setState(() => _led2 = value),
                                    ),
                                    _ExpectedSwitch(
                                      label: 'LED 3',
                                      value: _led3,
                                      enabled: !_isSending,
                                      onChanged: (value) =>
                                          setState(() => _led3 = value),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                TextField(
                                  controller: _noteController,
                                  enabled: !_isSending,
                                  maxLines: 3,
                                  decoration: const InputDecoration(
                                    labelText: 'Operator note',
                                    hintText:
                                        'Optional note stored with the command',
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _isSending ? null : _load,
                                        icon: const Icon(Icons.sync),
                                        label: const Text('Reload device'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed:
                                            _isSending ? null : _sendCommand,
                                        icon: _isSending
                                            ? const SizedBox(
                                                height: 18,
                                                width: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Icon(Icons.send_rounded),
                                        label: Text(
                                          _isSending
                                              ? 'Sending...'
                                              : 'Apply profile',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'LED health snapshot',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final columns =
                                  constraints.maxWidth >= 900 ? 3 : 1;
                              const spacing = 14.0;
                              final itemWidth = (constraints.maxWidth -
                                      (spacing * (columns - 1))) /
                                  columns;
                              final items = [
                                _LedCard(
                                  label: 'LED 1',
                                  reading: device?.led1Reading,
                                  expected: device?.led1Expected,
                                  working: device?.led1Working,
                                ),
                                _LedCard(
                                  label: 'LED 2',
                                  reading: device?.led2Reading,
                                  expected: device?.led2Expected,
                                  working: device?.led2Working,
                                ),
                                _LedCard(
                                  label: 'LED 3',
                                  reading: device?.led3Reading,
                                  expected: device?.led3Expected,
                                  working: device?.led3Working,
                                ),
                              ];

                              return Wrap(
                                spacing: spacing,
                                runSpacing: spacing,
                                children: items
                                    .map((item) =>
                                        SizedBox(width: itemWidth, child: item))
                                    .toList(),
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Telemetry trend',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          PanelCard(
                            child: SizedBox(
                              height: 280,
                              child: _TelemetryChart(entries: _telemetry),
                            ),
                          ),
                          const SizedBox(height: 24),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isWide = constraints.maxWidth >= 980;
                              return Flex(
                                direction:
                                    isWide ? Axis.horizontal : Axis.vertical,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _PayloadPanel(
                                      title: 'Latest status payload',
                                      payload: device?.lastStatusPayload,
                                    ),
                                  ),
                                  SizedBox(
                                    width: isWide ? 14 : 0,
                                    height: isWide ? 0 : 14,
                                  ),
                                  Expanded(
                                    child: _PayloadPanel(
                                      title: 'Latest telemetry payload',
                                      payload: device?.lastTelemetryPayload,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Recent acknowledgements',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          if (_statuses.isEmpty)
                            const _EmptyPanel(
                              message: 'No status acknowledgements stored yet.',
                            )
                          else
                            ..._statuses
                                .take(6)
                                .map((entry) => _StatusCard(entry: entry)),
                          const SizedBox(height: 24),
                          Text(
                            'Fault history',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          if (_faults.isEmpty)
                            const _EmptyPanel(
                              message:
                                  'No fault records stored for this node yet.',
                            )
                          else
                            ..._faults
                                .take(6)
                                .map((fault) => _FaultCard(entry: fault)),
                          const SizedBox(height: 24),
                          Text(
                            'Command history',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          if (_commands.isEmpty)
                            const _EmptyPanel(
                              message:
                                  'No commands have been sent to this node yet.',
                            )
                          else
                            ..._commands.take(8).map(
                                  (command) => _CommandCard(command: command),
                                ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}

class _DeviceHero extends StatelessWidget {
  const _DeviceHero({
    required this.device,
    required this.isOnline,
    required this.latestStatus,
  });

  final DeviceDetail? device;
  final bool isOnline;
  final StatusEntry? latestStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF11203B), Color(0xFF1B4466), Color(0xFF0A7F6F)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              StatusBadge(
                label: isOnline ? 'Online' : 'Idle',
                color: isOnline
                    ? const Color(0xFF79E0B9)
                    : const Color(0xFFD1D5DB),
                compact: true,
              ),
              StatusBadge(
                label: device?.hasFault == true
                    ? 'Fault detected'
                    : 'No active fault',
                color: device?.hasFault == true
                    ? const Color(0xFFFFA4A4)
                    : const Color(0xFF79E0B9),
                compact: true,
              ),
              if (latestStatus != null)
                StatusBadge(
                  label: latestStatus!.statusLabel,
                  color: const Color(0xFFFAC15C),
                  compact: true,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            device?.displayName ?? 'Device',
            style:
                theme.textTheme.headlineMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            device?.id ?? '--',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'The backend now stores expected LED state, actual working feedback, status acknowledgements, and auto-light configuration for this node.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _HeroMiniStat(
                label: 'Auto lights',
                value:
                    device?.autoLightsEnabled == true ? 'Enabled' : 'Disabled',
              ),
              _HeroMiniStat(
                label: 'Threshold',
                value: '${device?.autoLightThreshold ?? '--'}',
              ),
              _HeroMiniStat(
                label: 'Last period',
                value: device?.lastPeriod ?? 'Unknown',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMiniStat extends StatelessWidget {
  const _HeroMiniStat({required this.label, required this.value});

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
                ?.copyWith(color: Colors.white.withValues(alpha: 0.74)),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _InfoMetric extends StatelessWidget {
  const _InfoMetric({
    required this.title,
    required this.value,
    required this.caption,
  });

  final String title;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelLarge),
          const SizedBox(height: 10),
          Text(value, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(caption, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ExpectedSwitch extends StatelessWidget {
  const _ExpectedSwitch({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF11203B).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

class _LedCard extends StatelessWidget {
  const _LedCard({
    required this.label,
    required this.reading,
    required this.expected,
    required this.working,
  });

  final String label;
  final int? reading;
  final bool? expected;
  final bool? working;

  @override
  Widget build(BuildContext context) {
    final hasMismatch = expected == true && working == false;
    final accent =
        hasMismatch ? const Color(0xFFD64545) : const Color(0xFF0A7F6F);

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              StatusBadge(
                label: hasMismatch ? 'Mismatch' : 'Aligned',
                color: accent,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _DetailLine(label: 'Intensity', value: '${reading ?? '--'}'),
          _DetailLine(label: 'Expected', value: _onOff(expected)),
          _DetailLine(label: 'Working', value: _onOff(working)),
        ],
      ),
    );
  }
}

class _TelemetryChart extends StatelessWidget {
  const _TelemetryChart({required this.entries});

  final List<TelemetryEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(child: Text('No telemetry captured yet.'));
    }

    final points = entries.reversed.toList();
    final l1 = <FlSpot>[];
    final l2 = <FlSpot>[];
    final l3 = <FlSpot>[];

    for (var i = 0; i < points.length; i++) {
      final x = i.toDouble();
      l1.add(FlSpot(x, (points[i].ldr1 ?? 0).toDouble()));
      l2.add(FlSpot(x, (points[i].ldr2 ?? 0).toDouble()));
      l3.add(FlSpot(x, (points[i].ldr3 ?? 0).toDouble()));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _LegendDot(color: Color(0xFFF28C28), label: 'LDR 1'),
            _LegendDot(color: Color(0xFF0A7F6F), label: 'LDR 2'),
            _LegendDot(color: Color(0xFF18486B), label: 'LDR 3'),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: LineChart(
            LineChartData(
              minY: 0,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 500,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: const Color(0xFF11203B).withValues(alpha: 0.08),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                _line(l1, const Color(0xFFF28C28)),
                _line(l2, const Color(0xFF0A7F6F)),
                _line(l3, const Color(0xFF18486B)),
              ],
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    reservedSize: 44,
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toInt().toString(),
                        style: Theme.of(context).textTheme.bodySmall,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  LineChartBarData _line(List<FlSpot> points, Color color) {
    return LineChartBarData(
      spots: points,
      isCurved: true,
      color: color,
      barWidth: 3,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.09),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 10,
          width: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _PayloadPanel extends StatelessWidget {
  const _PayloadPanel({
    required this.title,
    required this.payload,
  });

  final String title;
  final Map<String, dynamic>? payload;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          SelectableText(
            payload == null
                ? 'No payload captured yet.'
                : const JsonEncoder.withIndent('  ').convert(payload),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.entry});

  final StatusEntry entry;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('MMM d, HH:mm');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PanelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatter.format(entry.receivedAt),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusBadge(
                  label: entry.statusLabel,
                  color: const Color(0xFF18486B),
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 10),
            _DetailLine(
              label: 'Command',
              value: entry.commandId ?? 'No command id',
            ),
            _DetailLine(
              label: 'Period',
              value: entry.period ?? 'Unknown',
            ),
            _DetailLine(
              label: 'Ambient',
              value:
                  '${entry.ambientValue ?? '--'} (${entry.ambientSource ?? 'n/a'})',
            ),
          ],
        ),
      ),
    );
  }
}

class _FaultCard extends StatelessWidget {
  const _FaultCard({required this.entry});

  final FaultEntry entry;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('MMM d, HH:mm');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PanelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatter.format(entry.receivedAt),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusBadge(
                  label: entry.hasFault ? 'Fault' : 'Clear',
                  color: entry.hasFault
                      ? const Color(0xFFD64545)
                      : const Color(0xFF0A7F6F),
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (entry.faultyLeds.isEmpty)
              Text(
                'No faulty LED details were included in this event.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              ...entry.faultyLeds.map(
                (led) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${led.channel}: ${led.reason} | expected ${_onOff(led.expected)} | working ${_onOff(led.working)} | reading ${led.reading ?? '--'}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CommandCard extends StatelessWidget {
  const _CommandCard({required this.command});

  final CommandEntry command;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('MMM d, HH:mm');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PanelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    command.commandName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusBadge(
                  label: command.status,
                  color: _commandColor(command.status),
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 10),
            _DetailLine(label: 'Command ID', value: command.commandId),
            _DetailLine(
              label: 'Sent',
              value:
                  '${formatter.format(command.createdAt)} by ${command.requestedBy}',
            ),
            if (command.note != null && command.note!.trim().isNotEmpty)
              _DetailLine(label: 'Note', value: command.note!),
            if (command.acknowledgedAt != null)
              _DetailLine(
                label: 'Ack',
                value: formatter.format(command.acknowledgedAt!),
              ),
            const SizedBox(height: 10),
            SelectableText(
              const JsonEncoder.withIndent('  ').convert(command.rawPayload),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

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
            width: 88,
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

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({
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
              const Icon(Icons.error_outline_rounded, size: 44),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
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

String _onOff(bool? value) {
  if (value == null) {
    return '--';
  }
  return value ? 'ON' : 'OFF';
}

Color _commandColor(String status) {
  final normalized = status.trim().toLowerCase();
  if (normalized == 'applied' ||
      normalized == 'sent' ||
      normalized == 'acknowledged') {
    return const Color(0xFF0A7F6F);
  }
  if (normalized == 'queued' || normalized == 'pending') {
    return const Color(0xFFF28C28);
  }
  return const Color(0xFF18486B);
}

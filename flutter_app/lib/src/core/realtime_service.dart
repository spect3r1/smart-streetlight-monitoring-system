import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'app_config.dart';
import 'models.dart';

class RealtimeService {
  final _streamController = StreamController<RealtimeEnvelope>.broadcast();
  final connectionState =
      ValueNotifier<ConnectionStatus>(ConnectionStatus.idle);

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  String? _token;
  bool _manualDisconnect = false;

  Stream<RealtimeEnvelope> get stream => _streamController.stream;

  Future<void> connect(String token) async {
    _token = token;
    _manualDisconnect = false;
    await _open();
  }

  Future<void> _open() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }

    await _subscription?.cancel();
    await _channel?.sink.close();
    _reconnectTimer?.cancel();

    connectionState.value = ConnectionStatus.connecting;
    final uri = AppConfig.wsUri(token);
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;

    _subscription = channel.stream.listen(
      (data) {
        connectionState.value = ConnectionStatus.connected;
        if (data is! String) {
          return;
        }
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) {
          _streamController.add(RealtimeEnvelope.fromJson(decoded));
        } else if (decoded is Map) {
          _streamController
              .add(RealtimeEnvelope.fromJson(decoded.cast<String, dynamic>()));
        }
      },
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
      cancelOnError: false,
    );
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _token == null || _token!.isEmpty) {
      connectionState.value = ConnectionStatus.disconnected;
      return;
    }
    connectionState.value = ConnectionStatus.reconnecting;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      unawaited(_open());
    });
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _token = null;
    _reconnectTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    _subscription = null;
    _channel = null;
    connectionState.value = ConnectionStatus.disconnected;
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _manualDisconnect = true;
    _token = null;
    _subscription?.cancel();
    _channel?.sink.close();
    _subscription = null;
    _channel = null;
    connectionState.value = ConnectionStatus.disconnected;
    _streamController.close();
    connectionState.dispose();
  }
}

enum ConnectionStatus {
  idle,
  connecting,
  connected,
  reconnecting,
  disconnected,
}

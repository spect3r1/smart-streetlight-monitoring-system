import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/realtime_service.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    required ApiClient apiClient,
    required RealtimeService realtimeService,
    required SharedPreferences preferences,
  })  : _apiClient = apiClient,
        _realtimeService = realtimeService,
        _preferences = preferences;

  static const _tokenKey = 'auth_token';
  static const _usernameKey = 'auth_username';
  static const _expiresKey = 'auth_expires_in';

  final ApiClient _apiClient;
  final RealtimeService _realtimeService;
  final SharedPreferences _preferences;

  UserSession? _session;
  bool _isBusy = false;
  String? _error;

  UserSession? get session => _session;
  bool get isBusy => _isBusy;
  bool get isAuthenticated => _session != null;
  String? get error => _error;

  Future<void> restoreSession() async {
    final token = _preferences.getString(_tokenKey);
    if (token == null || token.isEmpty) {
      return;
    }
    final username = _preferences.getString(_usernameKey) ?? 'operator';
    final expiresIn = _preferences.getInt(_expiresKey) ?? 3600;
    _apiClient.setToken(token);
    try {
      final verifiedUsername = await _apiClient.fetchMe();
      _session = UserSession(
          token: token,
          expiresIn: expiresIn,
          username: verifiedUsername.isEmpty ? username : verifiedUsername);
      await _realtimeService.connect(token);
    } catch (_) {
      await logout();
    }
    notifyListeners();
  }

  Future<bool> login({
    required String username,
    required String password,
  }) async {
    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      final session =
          await _apiClient.login(username: username, password: password);
      _session = session;
      await _preferences.setString(_tokenKey, session.token);
      await _preferences.setString(_usernameKey, session.username);
      await _preferences.setInt(_expiresKey, session.expiresIn);
      await _realtimeService.connect(session.token);
      return true;
    } catch (error) {
      _error = error.toString();
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _session = null;
    _error = null;
    _apiClient.setToken(null);
    await _realtimeService.disconnect();
    await _preferences.remove(_tokenKey);
    await _preferences.remove(_usernameKey);
    await _preferences.remove(_expiresKey);
    notifyListeners();
  }
}

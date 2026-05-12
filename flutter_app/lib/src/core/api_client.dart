import 'package:dio/dio.dart';

import 'app_config.dart';
import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient()
      : _dio = Dio(
          BaseOptions(
            baseUrl: AppConfig.apiBaseUrl,
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 18),
            sendTimeout: const Duration(seconds: 12),
            responseType: ResponseType.json,
          ),
        );

  final Dio _dio;

  void setToken(String? token) {
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('Authorization');
      return;
    }
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  Future<UserSession> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/auth/login',
        data: {'username': username, 'password': password},
      );
      final token = response.data?['access_token'] as String? ?? '';
      if (token.isEmpty) {
        throw const ApiException('Backend returned an empty access token.');
      }
      final expiresIn = response.data?['expires_in'] as int? ?? 3600;
      setToken(token);
      final profile = await fetchMe();
      return UserSession(
        token: token,
        expiresIn: expiresIn,
        username: profile,
      );
    } on DioException catch (error) {
      throw ApiException(_messageFromDio(error));
    }
  }

  Future<String> fetchMe() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/api/v1/me');
      return response.data?['username'] as String? ?? 'operator';
    } on DioException catch (error) {
      throw ApiException(_messageFromDio(error));
    }
  }

  Future<DashboardSummary> fetchDashboardSummary() async {
    try {
      final response =
          await _dio.get<Map<String, dynamic>>('/api/v1/dashboard/summary');
      return DashboardSummary.fromJson(response.data ?? const {});
    } on DioException catch (error) {
      throw ApiException(_messageFromDio(error));
    }
  }

  Future<List<DeviceSummary>> fetchDevices() async {
    try {
      final response = await _dio.get<List<dynamic>>('/api/v1/devices');
      return response.data
              ?.whereType<Map>()
              .map((item) =>
                  DeviceSummary.fromJson(item.cast<String, dynamic>()))
              .toList() ??
          const [];
    } on DioException catch (error) {
      throw ApiException(_messageFromDio(error));
    }
  }

  Future<DeviceDetail> fetchDevice(String deviceId) async {
    try {
      final response =
          await _dio.get<Map<String, dynamic>>('/api/v1/devices/$deviceId');
      return DeviceDetail.fromJson(response.data ?? const {});
    } on DioException catch (error) {
      throw ApiException(_messageFromDio(error));
    }
  }

  Future<List<TelemetryEntry>> fetchTelemetry(
    String deviceId, {
    int limit = 40,
  }) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/api/v1/devices/$deviceId/telemetry',
        queryParameters: {'limit': limit},
      );
      return response.data
              ?.whereType<Map>()
              .map((item) =>
                  TelemetryEntry.fromJson(item.cast<String, dynamic>()))
              .toList() ??
          const [];
    } on DioException catch (error) {
      throw ApiException(_messageFromDio(error));
    }
  }

  Future<List<StatusEntry>> fetchStatuses(
    String deviceId, {
    int limit = 20,
  }) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/api/v1/devices/$deviceId/status',
        queryParameters: {'limit': limit},
      );
      return response.data
              ?.whereType<Map>()
              .map((item) => StatusEntry.fromJson(item.cast<String, dynamic>()))
              .toList() ??
          const [];
    } on DioException catch (error) {
      throw ApiException(_messageFromDio(error));
    }
  }

  Future<List<FaultEntry>> fetchFaults(String deviceId,
      {int limit = 20}) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/api/v1/devices/$deviceId/faults',
        queryParameters: {'limit': limit},
      );
      return response.data
              ?.whereType<Map>()
              .map((item) => FaultEntry.fromJson(item.cast<String, dynamic>()))
              .toList() ??
          const [];
    } on DioException catch (error) {
      throw ApiException(_messageFromDio(error));
    }
  }

  Future<List<CommandEntry>> fetchCommands(
    String deviceId, {
    int limit = 20,
  }) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/api/v1/devices/$deviceId/commands',
        queryParameters: {'limit': limit},
      );
      return response.data
              ?.whereType<Map>()
              .map(
                  (item) => CommandEntry.fromJson(item.cast<String, dynamic>()))
              .toList() ??
          const [];
    } on DioException catch (error) {
      throw ApiException(_messageFromDio(error));
    }
  }

  Future<CommandEntry> sendCommand(
    String deviceId,
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/devices/$deviceId/commands',
        data: payload,
      );
      return CommandEntry.fromJson(response.data ?? const {});
    } on DioException catch (error) {
      throw ApiException(_messageFromDio(error));
    }
  }

  String _messageFromDio(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    if (data is Map && data['detail'] is List) {
      final joined = (data['detail'] as List)
          .map((entry) => entry is Map ? entry['msg'] : entry)
          .whereType<Object>()
          .join(', ');
      if (joined.isNotEmpty) {
        return joined;
      }
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Connection to ${AppConfig.apiBaseUri.host} timed out.';
    }
    return error.message ?? 'Unexpected API error';
  }
}

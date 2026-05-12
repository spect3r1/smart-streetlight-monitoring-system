class AppConfig {
  static const String _configuredApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://104.248.227.238:8000',
  );

  static Uri get apiBaseUri {
    final trimmed = _configuredApiBaseUrl.trim();
    final normalized = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    return Uri.parse(normalized);
  }

  static String get apiBaseUrl => apiBaseUri.toString();

  static Uri wsUri(String token) {
    final scheme = apiBaseUri.scheme == 'https' ? 'wss' : 'ws';
    return apiBaseUri.replace(
      scheme: scheme,
      path: '/ws/stream',
      queryParameters: {'token': token},
    );
  }
}

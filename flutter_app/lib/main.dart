import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app.dart';
import 'src/core/api_client.dart';
import 'src/core/realtime_service.dart';
import 'src/features/auth/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final apiClient = ApiClient();
  final realtimeService = RealtimeService();
  final authController = AuthController(
    apiClient: apiClient,
    realtimeService: realtimeService,
    preferences: preferences,
  );
  await authController.restoreSession();
  runApp(
    StreetlightApp(
      apiClient: apiClient,
      realtimeService: realtimeService,
      authController: authController,
    ),
  );
}

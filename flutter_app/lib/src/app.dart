import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/realtime_service.dart';
import 'core/theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/device_detail/device_detail_screen.dart';

class StreetlightApp extends StatelessWidget {
  const StreetlightApp({
    super.key,
    required this.apiClient,
    required this.realtimeService,
    required this.authController,
  });

  final ApiClient apiClient;
  final RealtimeService realtimeService;
  final AuthController authController;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      refreshListenable: authController,
      initialLocation: authController.isAuthenticated ? '/dashboard' : '/login',
      redirect: (context, state) {
        final isLoggedIn = authController.isAuthenticated;
        final onLogin = state.matchedLocation == '/login';
        if (!isLoggedIn && !onLogin) {
          return '/login';
        }
        if (isLoggedIn && onLogin) {
          return '/dashboard';
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/devices/:deviceId',
          builder: (context, state) => DeviceDetailScreen(
            deviceId: state.pathParameters['deviceId']!,
          ),
        ),
      ],
    );

    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: apiClient),
        Provider<RealtimeService>.value(value: realtimeService),
        ChangeNotifierProvider<AuthController>.value(value: authController),
      ],
      child: MaterialApp.router(
        title: 'Street Light Control',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        routerConfig: router,
      ),
    );
  }
}

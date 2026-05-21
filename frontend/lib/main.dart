import 'dart:io';

import 'package:flutter/material.dart';
import 'package:predection_desktop_app/core/di/injection_container.dart';
import 'package:predection_desktop_app/core/services/backend_process_service.dart';
import 'package:predection_desktop_app/core/theme/app_theme.dart';
import 'package:predection_desktop_app/features/admin/presentation/pages/admin_users_page.dart';
import 'package:predection_desktop_app/features/alerts/presentation/pages/alerts_page.dart';
import 'package:predection_desktop_app/features/analytics/presentation/pages/analytics_page.dart';
import 'package:predection_desktop_app/features/auth/presentation/pages/login_page.dart';
import 'package:predection_desktop_app/features/dashboard/presentation/pages/dashboard_page_simple.dart';
import 'package:predection_desktop_app/features/history/presentation/pages/history_page.dart';
import 'package:predection_desktop_app/features/predictions/presentation/pages/predictions_page.dart';
import 'package:predection_desktop_app/features/results/presentation/pages/results_page.dart';
import 'package:predection_desktop_app/features/settings/presentation/pages/settings_page.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  try {
    await BackendProcessService.instance.start();
  } catch (e) {
    debugPrint('Backend startup failed: $e');
    exit(1);
  }

  await configureDependencies();

  const windowOptions = WindowOptions(
    title: 'Engine Health Monitor',
    size: Size(1280, 800),
    minimumSize: Size(1000, 700),
    center: true,
  );

  await windowManager.setPreventClose(true);

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const BackendLifecycleWrapper(child: MyApp()));
}

class BackendLifecycleWrapper extends StatefulWidget {
  final Widget child;

  const BackendLifecycleWrapper({super.key, required this.child});

  @override
  State<BackendLifecycleWrapper> createState() =>
      _BackendLifecycleWrapperState();
}

class _BackendLifecycleWrapperState extends State<BackendLifecycleWrapper>
    with WindowListener {
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  Future<void> onWindowClose() async {
    if (_isClosing) {
      return;
    }

    _isClosing = true;

    try {
      await BackendProcessService.instance.stop();
    } catch (e) {
      debugPrint('Backend shutdown failed: $e');
    }

    await windowManager.setPreventClose(false);

    try {
      await windowManager.close();
    } catch (_) {
      await windowManager.destroy();
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Route<dynamic> _buildRoute(Widget page, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      opaque: true,
      maintainState: true,
      transitionDuration: const Duration(milliseconds: 140),
      reverseTransitionDuration: const Duration(milliseconds: 110),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final fadeAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        // Subtle fade only: no route slide/scale, so the new page does not feel
        // like a popup over the old page. The sidebar width animation is handled
        // inside MainLayout.
        return FadeTransition(
          opacity: fadeAnimation,
          child: child,
        );
      },
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final routeName = settings.name ?? '/';

    if (routeName == '/') {
      return _buildRoute(const LoginPage(), settings);
    }

    if (routeName == '/dashboard') {
      return _buildRoute(const DashboardPage(), settings);
    }

    if (routeName == '/predictions') {
      return _buildRoute(const PredictionsPage(), settings);
    }

    if (routeName == '/history') {
      return _buildRoute(const HistoryPage(), settings);
    }

    if (routeName == '/analytics') {
      return _buildRoute(const AnalyticsPage(), settings);
    }

    if (routeName == '/alerts') {
      return _buildRoute(const AlertsPage(), settings);
    }

    if (routeName == '/settings') {
      return _buildRoute(const SettingsPage(), settings);
    }

    if (routeName == '/admin/users') {
      return _buildRoute(const AdminUsersPage(), settings);
    }

    if (routeName == '/results' || routeName.startsWith('/results/')) {
      return _buildRoute(
        ResultsPage(
          predictionId: _predictionIdFromRoute(settings),
          initialResult: _initialResultFromRoute(settings),
        ),
        settings,
      );
    }

    return _buildRoute(
      UnknownRoutePage(routeName: routeName),
      settings,
    );
  }

  int? _predictionIdFromRoute(RouteSettings settings) {
    final routeName = settings.name ?? '';

    if (routeName.startsWith('/results/')) {
      final rawId = routeName.substring('/results/'.length);
      return int.tryParse(rawId);
    }

    final args = settings.arguments;

    if (args is int) {
      return args;
    }

    if (args is Map<String, dynamic>) {
      final value = args['predictionId'] ?? args['prediction_id'];

      if (value is int) {
        return value;
      }

      if (value is String) {
        return int.tryParse(value);
      }
    }

    if (args is Map) {
      final value = args['predictionId'] ?? args['prediction_id'];

      if (value is int) {
        return value;
      }

      if (value is String) {
        return int.tryParse(value);
      }
    }

    return null;
  }

  Map<String, dynamic>? _initialResultFromRoute(RouteSettings settings) {
    final args = settings.arguments;

    if (args is Map<String, dynamic>) {
      final value = args['initialResult'];

      if (value is Map<String, dynamic>) {
        return value;
      }

      if (value is Map) {
        return value.map(
          (key, dynamic item) => MapEntry(key.toString(), item),
        );
      }
    }

    if (args is Map) {
      final value = args['initialResult'];

      if (value is Map<String, dynamic>) {
        return value;
      }

      if (value is Map) {
        return value.map(
          (key, dynamic item) => MapEntry(key.toString(), item),
        );
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Engine Health Monitor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: '/',
      onGenerateRoute: _onGenerateRoute,
    );
  }
}

class UnknownRoutePage extends StatelessWidget {
  const UnknownRoutePage({
    super.key,
    required this.routeName,
  });

  final String routeName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          'Route not found: $routeName',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

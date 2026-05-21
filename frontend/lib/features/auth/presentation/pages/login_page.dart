import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Login page for Engine Health Monitor.
///
/// This version is connected to the backend `/login` API.
/// It only navigates to the dashboard when the backend returns:
/// `{ "message": "Login successful" }`.
class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    this.onAuthenticated,
    this.applicationName = 'Engine Health Monitor',
    this.systemSubtitle = 'Aircraft Engine Prediction System',
  });

  final Future<void> Function(LoginUser user)? onAuthenticated;
  final String applicationName;
  final String systemSubtitle;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class LoginUser {
  const LoginUser({
    required this.userId,
    required this.username,
  });

  final int userId;
  final String username;

  factory LoginUser.fromJson(Map<String, dynamic> json) {
    return LoginUser(
      userId: int.tryParse('${json['user_id'] ?? 0}') ?? 0,
      username: '${json['username'] ?? ''}',
    );
  }
}

class LoginApiClient {
  LoginApiClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: const String.fromEnvironment(
                  'BACKEND_BASE_URL',
                  defaultValue: 'http://127.0.0.1:8000',
                ),
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 15),
                sendTimeout: const Duration(seconds: 8),
                headers: const {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
                validateStatus: (status) => status != null && status < 500,
              ),
            );

  final Dio _dio;

  Future<LoginUser> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/login',
        data: {
          'username': username,
          'password': password,
        },
      );

      final data = response.data ?? <String, dynamic>{};
      final message = '${data['message'] ?? ''}'.trim();
      final error = '${data['error'] ?? ''}'.trim();

      if (response.statusCode == 200 && message == 'Login successful') {
        return LoginUser.fromJson(data);
      }

      if (error.isNotEmpty) {
        throw LoginException(error);
      }

      if (message.isNotEmpty) {
        throw LoginException(message);
      }

      throw const LoginException('Invalid username or password');
    } on DioException catch (error) {
      final responseData = error.response?.data;
      if (responseData is Map && responseData['error'] != null) {
        throw LoginException('${responseData['error']}');
      }

      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout) {
        throw const LoginException(
          'Cannot connect to the backend. Make sure the backend is running.',
        );
      }

      throw LoginException(error.message ?? 'Login request failed');
    }
  }
}

class LoginException implements Exception {
  const LoginException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _apiClient = LoginApiClient();

  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final user = await _apiClient.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      await _LoginSessionStore.saveUser(user);

      if (!mounted) return;

      if (widget.onAuthenticated != null) {
        await widget.onAuthenticated!(user);
      } else {
        final landingRoute = await _LandingPageRouteStore.readLandingRoute();
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(landingRoute);
      }
    } on LoginException catch (error) {
      _showLoginError(error.message);
    } catch (error) {
      _showLoginError('Sign in failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showLoginError(String message) {
    if (!mounted) return;

    // Keep the login error inside the card only.
    // No bottom snackbar is shown for invalid credentials.
    setState(() => _errorMessage = message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _LoginPalette.pageBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AppHeader(
                        applicationName: widget.applicationName,
                        systemSubtitle: widget.systemSubtitle,
                      ),
                      const SizedBox(height: 28),
                      _LoginCard(
                        formKey: _formKey,
                        usernameController: _usernameController,
                        passwordController: _passwordController,
                        obscurePassword: _obscurePassword,
                        isSubmitting: _isSubmitting,
                        errorMessage: _errorMessage,
                        onTogglePasswordVisibility: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                        onSubmit: _handleSignIn,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({
    required this.applicationName,
    required this.systemSubtitle,
  });

  final String applicationName;
  final String systemSubtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _LoginPalette.brandBlue,
            boxShadow: [
              BoxShadow(
                color: _LoginPalette.brandBlue.withOpacity(0.24),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.flight_rounded,
            size: 38,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          applicationName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: _LoginPalette.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          systemSubtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: _LoginPalette.textMuted,
          ),
        ),
      ],
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.usernameController,
    required this.passwordController,
    required this.obscurePassword,
    required this.isSubmitting,
    required this.errorMessage,
    required this.onTogglePasswordVisibility,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool isSubmitting;
  final String? errorMessage;
  final VoidCallback onTogglePasswordVisibility;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
      decoration: BoxDecoration(
        color: _LoginPalette.cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _LoginPalette.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A101828),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Sign In',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _LoginPalette.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter your credentials to access the dashboard',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _LoginPalette.textMuted,
              ),
            ),
            if (errorMessage != null && errorMessage!.trim().isNotEmpty) ...[
              const SizedBox(height: 18),
              _ErrorBanner(message: errorMessage!),
            ],
            const SizedBox(height: 26),
            const _FieldLabel('Username'),
            const SizedBox(height: 8),
            TextFormField(
              controller: usernameController,
              enabled: !isSubmitting,
              textInputAction: TextInputAction.next,
              decoration: _LoginInputDecoration(
                hintText: 'Enter your username',
                prefixIcon: Icons.person_outline_rounded,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Username is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 18),
            const _FieldLabel('Password'),
            const SizedBox(height: 8),
            TextFormField(
              controller: passwordController,
              enabled: !isSubmitting,
              obscureText: obscurePassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) {
                if (!isSubmitting) onSubmit();
              },
              decoration: _LoginInputDecoration(
                hintText: 'Enter your password',
                prefixIcon: Icons.lock_outline_rounded,
                suffixIcon: IconButton(
                  splashRadius: 20,
                  onPressed: isSubmitting ? null : onTogglePasswordVisibility,
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: _LoginPalette.textMuted,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Password is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: isSubmitting ? null : onSubmit,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: _LoginPalette.buttonBackground,
                  disabledBackgroundColor: _LoginPalette.buttonBackground,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Aviation Data Engineering System',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _LoginPalette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _LoginPalette.errorSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _LoginPalette.errorBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: _LoginPalette.errorColor,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _LoginPalette.errorColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: _LoginPalette.textPrimary,
      ),
    );
  }
}

class _LoginInputDecoration extends InputDecoration {
  _LoginInputDecoration({
    required String hintText,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) : super(
          hintText: hintText,
          prefixIcon: Icon(prefixIcon, size: 20, color: _LoginPalette.textMuted),
          suffixIcon: suffixIcon,
          hintStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _LoginPalette.hintText,
          ),
          filled: true,
          fillColor: _LoginPalette.inputBackground,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _LoginPalette.inputBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _LoginPalette.brandBlue, width: 1.2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _LoginPalette.errorColor),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _LoginPalette.errorColor, width: 1.2),
          ),
        );
}

class _LoginSessionStore {
  static Future<File> _sessionFile() async {
    final appData = Platform.environment['APPDATA'];
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final basePath = appData != null && appData.trim().isNotEmpty
        ? appData
        : '${home ?? '.'}${Platform.pathSeparator}.config';

    final directory = Directory(
      '$basePath${Platform.pathSeparator}EngineHealthMonitor',
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return File('${directory.path}${Platform.pathSeparator}current_user.json');
  }

  static Future<void> saveUser(LoginUser user) async {
    final file = await _sessionFile();
    await file.writeAsString(
      jsonEncode({
        'user_id': user.userId,
        'username': user.username,
        'saved_at': DateTime.now().toIso8601String(),
      }),
    );
  }
}

class _LandingPageRouteStore {
  static const Map<String, String> _landingRoutes = {
    'Dashboard': '/dashboard',
    'Predictions': '/predictions',
    'Results': '/results',
    'History': '/history',
    'Analytics': '/analytics',
    'Alerts': '/alerts',
  };

  static Future<String> readLandingRoute() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) {
        return '/dashboard';
      }

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        final landingPage = '${decoded['defaultLandingPage'] ?? 'Dashboard'}'.trim();
        return _landingRoutes[landingPage] ?? '/dashboard';
      }
    } catch (_) {
      // If settings cannot be read, fall back to the safe dashboard route.
    }

    return '/dashboard';
  }

  static Future<File> _settingsFile() async {
    final env = Platform.environment;
    final String basePath;

    if (Platform.isWindows && (env['APPDATA'] ?? '').isNotEmpty) {
      basePath = env['APPDATA']!;
    } else if ((env['HOME'] ?? '').isNotEmpty) {
      basePath = env['HOME']!;
    } else {
      basePath = Directory.current.path;
    }

    return File(
      '$basePath${Platform.pathSeparator}EngineHealthMonitor${Platform.pathSeparator}settings.json',
    );
  }
}

class _LoginPalette {
  static const pageBackground = Color(0xFFF5F7FB);
  static const cardBackground = Colors.white;
  static const border = Color(0xFFE4E7EC);
  static const inputBorder = Color(0xFFE5E7EB);
  static const inputBackground = Color(0xFFF9FAFB);
  static const brandBlue = Color(0xFF2563EB);
  static const buttonBackground = Color(0xFF030521);
  static const textPrimary = Color(0xFF111827);
  static const textMuted = Color(0xFF667085);
  static const hintText = Color(0xFF98A2B3);
  static const errorColor = Color(0xFFEF4444);
  static const errorSoft = Color(0xFFFFF1F2);
  static const errorBorder = Color(0xFFFECACA);
}

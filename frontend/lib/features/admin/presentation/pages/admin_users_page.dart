import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:predection_desktop_app/shared/layouts/main_layout.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final Dio _dio = Dio(
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

  String? _currentUsername;
  bool _isLoadingUser = true;
  bool _isCreating = false;
  _AppPopup? _popup;

  bool get _isAdmin => (_currentUsername ?? '').trim().toLowerCase() == 'admin';

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final username = await _AccountSessionStore.readUsername();
    if (!mounted) return;

    setState(() {
      _currentUsername = username;
      _isLoadingUser = false;
    });
  }

  Future<void> _createUser() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isCreating = true;
      _popup = null;
    });

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/admin/users',
        data: {
          'admin_username': _currentUsername,
          'username': _usernameController.text.trim(),
          'password': _passwordController.text,
        },
      );

      final data = response.data ?? <String, dynamic>{};
      final error = data['error']?.toString();

      if (response.statusCode == 200 && (error == null || error.isEmpty)) {
        _usernameController.clear();
        _passwordController.clear();
        _confirmPasswordController.clear();

        _showPopup(
          const _AppPopup(
            title: 'User created',
            message: 'The new user account was created successfully.',
            isError: false,
          ),
        );
      } else {
        _showPopup(
          _AppPopup(
            title: 'Create failed',
            message: error?.isNotEmpty == true
                ? error!
                : 'The backend could not create this user.',
            isError: true,
          ),
        );
      }
    } on DioException catch (error) {
      _showPopup(
        _AppPopup(
          title: 'Create failed',
          message: error.message ?? 'Unable to reach the backend API.',
          isError: true,
        ),
      );
    } catch (error) {
      _showPopup(
        _AppPopup(
          title: 'Create failed',
          message: '$error',
          isError: true,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  void _showPopup(_AppPopup popup) {
    if (!mounted) return;

    setState(() => _popup = popup);

    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      if (_popup == popup) {
        setState(() => _popup = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      currentRoute: '/admin/users',
      child: Stack(
        children: [
          _isLoadingUser
              ? const Center(child: CircularProgressIndicator())
              : _isAdmin
                  ? _AdminUsersContent(
                      formKey: _formKey,
                      usernameController: _usernameController,
                      passwordController: _passwordController,
                      confirmPasswordController: _confirmPasswordController,
                      isCreating: _isCreating,
                      onCreateUser: _createUser,
                    )
                  : const _AdminAccessDenied(),
          Positioned(
            right: 24,
            bottom: 24,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _popup == null
                  ? const SizedBox.shrink()
                  : _PopupCard(
                      key: ValueKey('${_popup!.title}-${_popup!.message}'),
                      popup: _popup!,
                      onClose: () => setState(() => _popup = null),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminUsersContent extends StatelessWidget {
  const _AdminUsersContent({
    required this.formKey,
    required this.usernameController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.isCreating,
    required this.onCreateUser,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool isCreating;
  final VoidCallback onCreateUser;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 42),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Admin Users',
                style: GoogleFonts.inter(
                  color: _AdminPalette.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create dashboard user accounts for the Engine Health Monitor app.',
                style: GoogleFonts.inter(
                  color: _AdminPalette.textMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 26),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _AdminPalette.border),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x08000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create New User',
                        style: GoogleFonts.inter(
                          color: _AdminPalette.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The password will be hashed by the backend before it is stored.',
                        style: GoogleFonts.inter(
                          color: _AdminPalette.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _FieldLabel('Username'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: usernameController,
                        textInputAction: TextInputAction.next,
                        decoration: _AdminInputDecoration(
                          hintText: 'Enter new username',
                          prefixIcon: Icons.person_add_alt_1_outlined,
                        ),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) return 'Username is required';
                          if (text.length < 3) return 'Username must be at least 3 characters';
                          if (text.contains(RegExp(r'\s'))) return 'Username cannot contain spaces';
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),
                      _FieldLabel('Password'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: passwordController,
                        obscureText: true,
                        textInputAction: TextInputAction.next,
                        decoration: _AdminInputDecoration(
                          hintText: 'Enter password',
                          prefixIcon: Icons.lock_outline_rounded,
                        ),
                        validator: (value) {
                          final text = value ?? '';
                          if (text.isEmpty) return 'Password is required';
                          if (text.length < 6) return 'Password must be at least 6 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),
                      _FieldLabel('Confirm Password'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: confirmPasswordController,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => onCreateUser(),
                        decoration: _AdminInputDecoration(
                          hintText: 'Re-enter password',
                          prefixIcon: Icons.verified_user_outlined,
                        ),
                        validator: (value) {
                          if ((value ?? '').isEmpty) return 'Confirm password is required';
                          if (value != passwordController.text) return 'Passwords do not match';
                          return null;
                        },
                      ),
                      const SizedBox(height: 26),
                      SizedBox(
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: isCreating ? null : onCreateUser,
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: _AdminPalette.buttonBackground,
                            disabledBackgroundColor: _AdminPalette.buttonBackground.withOpacity(0.62),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: isCreating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.person_add_alt_1_rounded, size: 18),
                          label: Text(
                            isCreating ? 'Creating...' : 'Create User',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminAccessDenied extends StatelessWidget {
  const _AdminAccessDenied();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _AdminPalette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.admin_panel_settings_outlined, color: _AdminPalette.error, size: 44),
            const SizedBox(height: 16),
            Text(
              'Admin access required',
              style: GoogleFonts.inter(
                color: _AdminPalette.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Only the admin user can create new user accounts.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: _AdminPalette.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pushReplacementNamed('/dashboard'),
              child: const Text('Back to Dashboard'),
            ),
          ],
        ),
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
      style: GoogleFonts.inter(
        color: _AdminPalette.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _AdminInputDecoration extends InputDecoration {
  _AdminInputDecoration({
    required String hintText,
    required IconData prefixIcon,
  }) : super(
          hintText: hintText,
          prefixIcon: Icon(prefixIcon, size: 20, color: _AdminPalette.textMuted),
          hintStyle: GoogleFonts.inter(
            color: _AdminPalette.hintText,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          filled: true,
          fillColor: _AdminPalette.inputBackground,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _AdminPalette.inputBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _AdminPalette.brandBlue, width: 1.2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _AdminPalette.error),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _AdminPalette.error, width: 1.2),
          ),
        );
}

class _AppPopup {
  const _AppPopup({
    required this.title,
    required this.message,
    required this.isError,
  });

  final String title;
  final String message;
  final bool isError;
}

class _PopupCard extends StatelessWidget {
  const _PopupCard({
    super.key,
    required this.popup,
    required this.onClose,
  });

  final _AppPopup popup;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final color = popup.isError ? _AdminPalette.error : _AdminPalette.success;
    final background = popup.isError ? const Color(0xFFFFF1F2) : const Color(0xFFECFDF5);
    final border = popup.isError ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                popup.isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    popup.title,
                    style: GoogleFonts.inter(
                      color: _AdminPalette.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    popup.message,
                    style: GoogleFonts.inter(
                      color: _AdminPalette.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded, size: 18),
              color: _AdminPalette.textMuted,
              splashRadius: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountSessionStore {
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

  static Future<String?> readUsername() async {
    try {
      final file = await _sessionFile();
      if (!await file.exists()) return null;

      final payload = jsonDecode(await file.readAsString());
      if (payload is Map<String, dynamic>) {
        return payload['username']?.toString();
      }

      if (payload is Map) {
        return payload['username']?.toString();
      }
    } catch (_) {
      return null;
    }

    return null;
  }
}

class _AdminPalette {
  static const border = Color(0xFFE2E8F0);
  static const inputBorder = Color(0xFFE5E7EB);
  static const inputBackground = Color(0xFFF9FAFB);
  static const brandBlue = Color(0xFF2563EB);
  static const buttonBackground = Color(0xFF030521);
  static const textPrimary = Color(0xFF111827);
  static const textMuted = Color(0xFF64748B);
  static const hintText = Color(0xFF98A2B3);
  static const error = Color(0xFFEF4444);
  static const success = Color(0xFF22C55E);
}

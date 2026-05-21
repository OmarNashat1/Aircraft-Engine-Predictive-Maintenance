import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:predection_desktop_app/cubits/auth/auth_state.dart';

/// Authentication Cubit
/// Manages authentication state
class AuthCubit extends Cubit<AuthState> {
  AuthCubit() : super(const AuthInitial());

  /// login accepts any credentials
  /// In real implementation, this would call authentication API
  Future<void> login(String username, String password) async {
    emit(const AuthLoading());

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    // For prototype: accept any non-empty credentials
    if (username.isNotEmpty && password.isNotEmpty) {
      emit(AuthAuthenticated(username: username));
    } else {
      emit(
        const AuthUnauthenticated(
          errorMessage: 'Please enter username and password',
        ),
      );
    }
  }

  /// Logout user
  void logout() {
    emit(const AuthUnauthenticated());
  }

  /// Check if user is authenticated
  bool get isAuthenticated => state is AuthAuthenticated;

  /// Get current username if authenticated
  String? get currentUsername {
    if (state is AuthAuthenticated) {
      return (state as AuthAuthenticated).username;
    }
    return null;
  }
}

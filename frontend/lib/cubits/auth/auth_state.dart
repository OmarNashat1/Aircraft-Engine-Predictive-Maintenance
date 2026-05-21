import 'package:equatable/equatable.dart';

/// Authentication states
abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

/// Initial state - user not authenticated
class AuthInitial extends AuthState {
  const AuthInitial();
}

/// Loading state - authentication in progress
class AuthLoading extends AuthState {
  const AuthLoading();
}

/// Authenticated state - user logged in successfully
class AuthAuthenticated extends AuthState {
  final String username;

  const AuthAuthenticated({required this.username});

  @override
  List<Object?> get props => [username];
}

/// Unauthenticated state - user logged out or login failed
class AuthUnauthenticated extends AuthState {
  final String? errorMessage;

  const AuthUnauthenticated({this.errorMessage});

  @override
  List<Object?> get props => [errorMessage];
}

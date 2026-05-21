import 'package:dartz/dartz.dart';
import 'package:predection_desktop_app/core/error/failures.dart';
import 'package:predection_desktop_app/features/auth/domain/entities/user_entity.dart';

/// Auth repository interface (Domain layer)
/// Implementation will be in Data layer
abstract class AuthRepository {
  /// Login with username and password
  Future<Either<Failure, UserEntity>> login({
    required String username,
    required String password,
  });

  /// Logout current user
  Future<Either<Failure, void>> logout();

  /// Check if user is authenticated
  Future<bool> isAuthenticated();
}

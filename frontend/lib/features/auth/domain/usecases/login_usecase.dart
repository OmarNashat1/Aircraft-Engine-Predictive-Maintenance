import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:predection_desktop_app/core/error/failures.dart';
import 'package:predection_desktop_app/features/auth/domain/entities/user_entity.dart';
import 'package:predection_desktop_app/features/auth/domain/repositories/auth_repository.dart';

/// Login use case - handles business logic for login
@injectable
class LoginUseCase {
  final AuthRepository repository;

  LoginUseCase(this.repository);

  Future<Either<Failure, UserEntity>> call({
    required String username,
    required String password,
  }) async {
    // Validate inputs
    if (username.isEmpty) {
      return const Left(ValidationFailure('Username cannot be empty'));
    }

    if (password.isEmpty) {
      return const Left(ValidationFailure('Password cannot be empty'));
    }

    // Call repository
    return await repository.login(username: username, password: password);
  }
}

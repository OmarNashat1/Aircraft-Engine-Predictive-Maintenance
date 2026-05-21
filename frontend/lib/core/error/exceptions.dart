/// Base exception class
class AppException implements Exception {
  final String message;
  final int? statusCode;

  AppException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

/// Server exception (5xx)
class ServerException extends AppException {
  ServerException([super.message = 'Server error', super.statusCode]);
}

/// Network exception (connection issues)
class NetworkException extends AppException {
  NetworkException([super.message = 'Network error']);
}

/// Authentication exception (401, 403)
class AuthException extends AppException {
  AuthException([super.message = 'Authentication error', super.statusCode]);
}

/// Validation exception (400)
class ValidationException extends AppException {
  ValidationException([super.message = 'Validation error', super.statusCode]);
}

/// Not found exception (404)
class NotFoundException extends AppException {
  NotFoundException([super.message = 'Not found', super.statusCode]);
}

/// Cache exception
class CacheException extends AppException {
  CacheException([super.message = 'Cache error']);
}

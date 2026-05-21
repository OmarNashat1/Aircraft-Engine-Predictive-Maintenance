import 'package:dio/dio.dart';
import 'package:predection_desktop_app/core/error/exceptions.dart';

/// Interceptor to handle HTTP errors and convert to exceptions
class ErrorInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    print('✅ Response received: ${response.statusCode}');
    print('✅ Response data: ${response.data}');
    print('✅ Response headers: ${response.headers}');
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    print('❌ Error Type: ${err.type}');
    print('❌ Error Message: ${err.message}');
    print('❌ Response Status: ${err.response?.statusCode}');
    print('❌ Response Data: ${err.response?.data}');

    AppException exception;

    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        exception = NetworkException(
          'Connection timeout. Please check your network.',
        );
        break;

      case DioExceptionType.badResponse:
        final statusCode = err.response?.statusCode;
        final message =
            err.response?.data?['message'] ??
            err.response?.data?['error'] ??
            'Request failed';

        if (statusCode != null) {
          if (statusCode >= 500) {
            exception = ServerException(message, statusCode);
          } else if (statusCode == 401 || statusCode == 403) {
            exception = AuthException(message, statusCode);
          } else if (statusCode == 404) {
            exception = NotFoundException(message, statusCode);
          } else if (statusCode == 400) {
            exception = ValidationException(message, statusCode);
          } else {
            exception = ServerException(message, statusCode);
          }
        } else {
          exception = ServerException(message);
        }
        break;

      case DioExceptionType.cancel:
        exception = NetworkException('Request cancelled');
        break;

      case DioExceptionType.unknown:
        if (err.error.toString().contains('SocketException')) {
          exception = NetworkException('No internet connection');
        } else {
          exception = NetworkException('Unexpected error: ${err.message}');
        }
        break;

      default:
        exception = NetworkException('Network error occurred');
    }

    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        error: exception,
        type: err.type,
        response: err.response,
      ),
    );
  }
}

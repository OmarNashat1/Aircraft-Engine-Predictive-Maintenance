import 'package:injectable/injectable.dart';
import 'package:predection_desktop_app/core/constants/api_constants.dart';
import 'package:predection_desktop_app/core/error/exceptions.dart';
import 'package:predection_desktop_app/core/network/dio_client.dart';
import 'package:predection_desktop_app/features/auth/data/models/user_model.dart';

/// Remote data source for authentication
@injectable
class AuthRemoteDataSource {
  final DioClient dioClient;

  AuthRemoteDataSource(this.dioClient);

  /// Login with username and password
  Future<UserModel> login({
    required String username,
    required String password,
  }) async {
    try {
      print('🔐 Attempting login for user: $username');

      // POST request with JSON body
      final response = await dioClient.post(
        ApiConstants.login,
        data: {'username': username, 'password': password},
      );

      print('✅ Login Response Status: ${response.statusCode}');
      print('✅ Login Response Data: ${response.data}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;

        // Handle response - expecting just a string token or success message
        if (data is String) {
          // If response is just a string (token or message)
          print('📦 Response is String: $data');
          return UserModel(
            id: '1', // Default ID since not provided
            username: username,
          );
        } else if (data is Map<String, dynamic>) {
          // If response is JSON object
          print('📦 Response is Map, parsing user data...');

          // Check if it contains user data
          if (data.containsKey('user_id') || data.containsKey('username')) {
            print('📦 Using direct response data');
            return UserModel.fromJson(data);
          } else if (data.containsKey('user')) {
            print('📦 Found "user" key in response');
            return UserModel.fromJson(data['user']);
          } else if (data.containsKey('data')) {
            print('📦 Found "data" key in response');
            return UserModel.fromJson(data['data']);
          } else {
            // Response might just be a success message
            print('📦 Response is success message, creating user');
            return UserModel(id: '1', username: username);
          }
        }

        throw ServerException('Invalid response format');
      } else if (response.statusCode == 422) {
        print('❌ Validation Error: ${response.data}');
        throw ValidationException('Invalid username or password');
      } else {
        print('❌ Login failed with status: ${response.statusCode}');
        throw ServerException('Login failed', response.statusCode);
      }
    } catch (e) {
      print('❌ Login Error: $e');
      if (e is AppException) rethrow;

      // Handle specific error messages
      if (e.toString().contains('422')) {
        throw ValidationException('Invalid username or password');
      }

      throw ServerException('Login failed: ${e.toString()}');
    }
  }

  /// Logout
  Future<void> logout() async {
    try {
      await dioClient.post(ApiConstants.logout);
    } catch (e) {
      // Logout can fail silently
      print('Logout error: $e');
    }
  }
}

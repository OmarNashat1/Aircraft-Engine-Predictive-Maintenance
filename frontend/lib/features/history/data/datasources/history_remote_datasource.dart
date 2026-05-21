import 'package:injectable/injectable.dart';
import 'package:predection_desktop_app/core/constants/api_constants.dart';
import 'package:predection_desktop_app/core/error/exceptions.dart';
import 'package:predection_desktop_app/core/network/dio_client.dart';
import 'package:predection_desktop_app/features/history/data/models/history_model.dart';

/// Remote data source for history
@injectable
class HistoryRemoteDataSource {
  final DioClient dioClient;

  HistoryRemoteDataSource(this.dioClient);

  /// Get prediction history
  Future<List<HistoryModel>> getHistory() async {
    try {
      print('📜 Fetching prediction history...');

      final response = await dioClient.get(ApiConstants.history);

      print('✅ History Response: ${response.statusCode}');
      print('📥 Response Data: ${response.data}');

      if (response.statusCode == 200) {
        final data = response.data;

        if (data is List) {
          return data.map((json) => HistoryModel.fromJson(json)).toList();
        }

        throw ServerException('Invalid response format');
      } else {
        throw ServerException('Failed to get history', response.statusCode);
      }
    } catch (e) {
      print('❌ History Error: $e');
      if (e is AppException) rethrow;
      throw ServerException('Failed to get history: ${e.toString()}');
    }
  }
}

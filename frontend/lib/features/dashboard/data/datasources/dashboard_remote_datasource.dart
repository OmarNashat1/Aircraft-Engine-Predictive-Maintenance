import 'package:injectable/injectable.dart';
import 'package:predection_desktop_app/core/constants/api_constants.dart';
import 'package:predection_desktop_app/core/error/exceptions.dart';
import 'package:predection_desktop_app/core/network/dio_client.dart';
import 'package:predection_desktop_app/features/dashboard/data/models/dashboard_summary_model.dart';

/// Remote data source for dashboard
@injectable
class DashboardRemoteDataSource {
  final DioClient dioClient;

  DashboardRemoteDataSource(this.dioClient);

  /// Get dashboard summary (fleet health + active alerts)
  Future<DashboardSummaryModel> getDashboardSummary() async {
    try {
      print('📊 Fetching dashboard summary...');

      final response = await dioClient.get(ApiConstants.dashboardSummary);

      print('✅ Dashboard Response: ${response.statusCode}');
      print('📥 Response Data: ${response.data}');

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return DashboardSummaryModel.fromJson(data);
        }
        throw ServerException('Invalid response format');
      } else {
        throw ServerException(
          'Failed to get dashboard summary',
          response.statusCode,
        );
      }
    } catch (e) {
      print('❌ Dashboard Error: $e');
      if (e is AppException) rethrow;
      throw ServerException('Failed to get dashboard summary: ${e.toString()}');
    }
  }
}

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:predection_desktop_app/core/constants/api_constants.dart';
import 'package:predection_desktop_app/core/error/exceptions.dart';
import 'package:predection_desktop_app/core/network/dio_client.dart';
import 'package:predection_desktop_app/features/predictions/data/models/prediction_result_model.dart';

/// Remote data source for predictions
@injectable
class PredictionRemoteDataSource {
  final DioClient dioClient;

  PredictionRemoteDataSource(this.dioClient);

  /// Upload CSV and run prediction
  Future<PredictionResultModel> runPrediction({
    required File csvFile,
    Function(double)? onProgress,
  }) async {
    try {
      // Create multipart form data
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          csvFile.path,
          filename: csvFile.path.split(Platform.pathSeparator).last,
        ),
      });

      print('📤 Uploading CSV file: ${csvFile.path}');

      // Increase timeout for prediction endpoint (5 minutes)
      final response = await dioClient.post(
        ApiConstants.uploadCsv,
        data: formData,
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 2),
        ),
        onSendProgress: (sent, total) {
          if (onProgress != null && total > 0) {
            final progress = sent / total;
            onProgress(progress);
            print(
              '📊 Upload progress: ${(progress * 100).toStringAsFixed(1)}%',
            );
          }
        },
      );

      print('✅ Prediction Response: ${response.statusCode}');
      print('📥 Response Data: ${response.data}');

      if (response.statusCode == 200) {
        return PredictionResultModel.fromJson(response.data);
      } else {
        throw ServerException('Prediction failed', response.statusCode);
      }
    } catch (e) {
      print('❌ Prediction Error: $e');
      if (e is AppException) rethrow;
      throw ServerException('Failed to run prediction: ${e.toString()}');
    }
  }
}

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

Future<void> uploadCsvThenOpenResults({
  required BuildContext context,
  required String csvPath,
}) async {
  final dio = Dio(
    BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 240),
      sendTimeout: const Duration(seconds: 240),
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  final fileName = p.basename(csvPath);

  final uploadResponse = await dio.post<dynamic>(
    '/upload-csv',
    data: FormData.fromMap({
      'file': await MultipartFile.fromFile(csvPath, filename: fileName),
    }),
  );

  final uploadData = _asMap(uploadResponse.data);
  if (uploadResponse.statusCode == null || uploadResponse.statusCode! >= 400) {
    throw Exception(_backendErrorMessage(uploadData, uploadResponse.data));
  }

  if (uploadData.containsKey('error')) {
    throw Exception(uploadData['error']);
  }

  final predictionJson = _asMap(uploadData['prediction']);
  final reportJson = _asMap(uploadData['report']);

  final unit = _asInt(
    predictionJson['unit'] ??
        predictionJson['engine_id'] ??
        reportJson['unit'] ??
        reportJson['engine_id'],
  );
  final cycle = _asInt(
    predictionJson['cycle'] ??
        predictionJson['cycle_id'] ??
        reportJson['cycle'] ??
        reportJson['cycle_id'],
  );

  // /upload-csv saves the prediction in the database, but returns the ML body.
  // The saved prediction_id is resolved from /history after upload completes.
  final predictionId = await _resolveSavedPredictionId(
    dio: dio,
    unit: unit,
    cycle: cycle,
  );

  if (!context.mounted) return;

  Navigator.of(context).pushReplacementNamed('/results/$predictionId');
}

Future<int> _resolveSavedPredictionId({
  required Dio dio,
  required int? unit,
  required int? cycle,
}) async {
  // Retry briefly because the DB commit and history fetch can occasionally race
  // on slower machines after a heavy prediction request.
  Exception? lastError;

  for (var attempt = 0; attempt < 6; attempt++) {
    if (attempt > 0) {
      await Future<void>.delayed(Duration(milliseconds: 250 + attempt * 150));
    }

    try {
      final historyResponse = await dio.get<dynamic>('/history');
      final historyData = historyResponse.data;

      if (historyResponse.statusCode == null || historyResponse.statusCode! >= 400) {
        throw Exception('Could not load prediction history.');
      }

      if (historyData is Map && historyData.containsKey('error')) {
        throw Exception(historyData['error']);
      }

      final historyItems = _asListOfMaps(historyData);
      if (historyItems.isEmpty) {
        throw Exception('Prediction was generated, but no saved history row was found.');
      }

      Map<String, dynamic> selected = historyItems.first;

      if (unit != null && cycle != null) {
        selected = historyItems.firstWhere(
          (item) => _asInt(item['engine_id']) == unit && _asInt(item['cycle_id']) == cycle,
          orElse: () => historyItems.first,
        );
      }

      final predictionId = _asInt(selected['prediction_id']);
      if (predictionId == null) {
        throw Exception('History row did not contain a prediction_id.');
      }

      return predictionId;
    } catch (error) {
      lastError = error is Exception ? error : Exception(error.toString());
    }
  }

  throw lastError ?? Exception('Could not resolve the saved prediction id.');
}

String _backendErrorMessage(Map<String, dynamic> data, Object? rawData) {
  if (data.containsKey('error')) return data['error'].toString();
  if (data.containsKey('detail')) return data['detail'].toString();
  return rawData?.toString() ?? 'Backend request failed.';
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, dynamic item) => MapEntry(key.toString(), item));
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _asListOfMaps(Object? value) {
  if (value is! List) return <Map<String, dynamic>>[];

  return value
      .whereType<Map>()
      .map((item) => item.map((key, dynamic val) => MapEntry(key.toString(), val)))
      .toList();
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

import 'package:injectable/injectable.dart';
import 'package:predection_desktop_app/features/predictions/domain/entities/prediction_result_entity.dart';

/// Service to store and retrieve the last prediction result
/// This allows the result to persist across navigation
@lazySingleton
class PredictionStorageService {
  PredictionResultEntity? _lastPredictionResult;

  /// Get the last prediction result
  PredictionResultEntity? get lastResult => _lastPredictionResult;

  /// Check if there is a stored result
  bool get hasResult => _lastPredictionResult != null;

  /// Store a new prediction result
  void saveResult(PredictionResultEntity result) {
    _lastPredictionResult = result;
  }

  /// Clear the stored result
  void clearResult() {
    _lastPredictionResult = null;
  }
}

import 'package:injectable/injectable.dart';
import 'package:predection_desktop_app/core/database/database_service.dart';
import 'package:predection_desktop_app/features/history/data/models/prediction_history_model.dart';

/// Local data source for history
@injectable
class HistoryLocalDataSource {
  final DatabaseService databaseService;

  HistoryLocalDataSource(this.databaseService);

  Future<List<PredictionHistoryModel>> getAllHistory() async {
    final maps = await databaseService.getAllPredictions();
    return maps.map((map) => PredictionHistoryModel.fromMap(map)).toList();
  }

  Future<List<PredictionHistoryModel>> getFilteredHistory({
    String? engineId,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final maps = await databaseService.getFilteredPredictions(
      engineId: engineId,
      status: status,
      startDate: startDate,
      endDate: endDate,
    );
    return maps.map((map) => PredictionHistoryModel.fromMap(map)).toList();
  }

  Future<void> savePrediction({
    required String predictionId,
    required String engineId,
    required int unit,
    required int cycle,
    required int predictedRul,
    required String riskLevel,
    required String status,
    String? notes,
  }) async {
    await databaseService.savePrediction(
      predictionId: predictionId,
      engineId: engineId,
      unit: unit,
      cycle: cycle,
      predictedRul: predictedRul,
      riskLevel: riskLevel,
      status: status,
      notes: notes,
    );
  }

  Future<void> deletePrediction(String predictionId) async {
    await databaseService.deletePrediction(predictionId);
  }

  Future<void> clearHistory() async {
    await databaseService.clearHistory();
  }
}

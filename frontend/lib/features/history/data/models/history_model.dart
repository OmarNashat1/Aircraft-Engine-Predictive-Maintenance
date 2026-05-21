import 'package:predection_desktop_app/features/history/domain/entities/history_entity.dart';

/// History data model with JSON serialization
class HistoryModel extends HistoryEntity {
  const HistoryModel({
    required super.runId,
    required super.predictionId,
    required super.engineId,
    required super.cycleId,
    required super.dataTimestamp,
    required super.predictedRul,
    required super.time,
    required super.status,
  });

  factory HistoryModel.fromJson(Map<String, dynamic> json) {
    return HistoryModel(
      runId: json['run_id']?.toString() ?? '',
      predictionId: json['prediction_id']?.toString() ?? '',
      engineId: json['engine_id']?.toString() ?? '',
      cycleId: json['cycle_id']?.toString() ?? '',
      dataTimestamp: json['data_timestamp']?.toString() ?? '',
      predictedRul: (json['predicted_rul'] is int)
          ? (json['predicted_rul'] as int).toDouble()
          : (json['predicted_rul'] as double? ?? 0.0),
      time: json['time']?.toString() ?? '',
      status: json['status']?.toString() ?? 'Unknown',
    );
  }

  HistoryEntity toEntity() {
    return HistoryEntity(
      runId: runId,
      predictionId: predictionId,
      engineId: engineId,
      cycleId: cycleId,
      dataTimestamp: dataTimestamp,
      predictedRul: predictedRul,
      time: time,
      status: status,
    );
  }
}

import 'package:predection_desktop_app/features/history/domain/entities/prediction_history_entity.dart';

/// Prediction History data model
class PredictionHistoryModel extends PredictionHistoryEntity {
  const PredictionHistoryModel({
    required super.id,
    required super.predictionId,
    required super.engineId,
    required super.unit,
    required super.cycle,
    required super.predictedRul,
    required super.riskLevel,
    required super.status,
    super.notes,
    required super.timestamp,
  });

  factory PredictionHistoryModel.fromMap(Map<String, dynamic> map) {
    return PredictionHistoryModel(
      id: map['id'] as int,
      predictionId: map['prediction_id'] as String,
      engineId: map['engine_id'] as String,
      unit: map['unit'] as int,
      cycle: map['cycle'] as int,
      predictedRul: map['predicted_rul'] as int,
      riskLevel: map['risk_level'] as String,
      status: map['status'] as String,
      notes: map['notes'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'prediction_id': predictionId,
      'engine_id': engineId,
      'unit': unit,
      'cycle': cycle,
      'predicted_rul': predictedRul,
      'risk_level': riskLevel,
      'status': status,
      'notes': notes,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  PredictionHistoryEntity toEntity() {
    return PredictionHistoryEntity(
      id: id,
      predictionId: predictionId,
      engineId: engineId,
      unit: unit,
      cycle: cycle,
      predictedRul: predictedRul,
      riskLevel: riskLevel,
      status: status,
      notes: notes,
      timestamp: timestamp,
    );
  }
}

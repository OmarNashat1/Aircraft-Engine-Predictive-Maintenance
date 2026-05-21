import 'package:equatable/equatable.dart';

/// Prediction History entity
class PredictionHistoryEntity extends Equatable {
  final int id;
  final String predictionId; // Run ID
  final String engineId;
  final int unit;
  final int cycle;
  final int predictedRul;
  final String riskLevel;
  final String status; // OK, Watch, Critical
  final String? notes;
  final DateTime timestamp;

  const PredictionHistoryEntity({
    required this.id,
    required this.predictionId,
    required this.engineId,
    required this.unit,
    required this.cycle,
    required this.predictedRul,
    required this.riskLevel,
    required this.status,
    this.notes,
    required this.timestamp,
  });

  @override
  List<Object?> get props => [
    id,
    predictionId,
    engineId,
    unit,
    cycle,
    predictedRul,
    riskLevel,
    status,
    notes,
    timestamp,
  ];
}

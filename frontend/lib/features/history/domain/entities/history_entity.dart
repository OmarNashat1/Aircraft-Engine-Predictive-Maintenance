import 'package:equatable/equatable.dart';

/// History entity for prediction runs
class HistoryEntity extends Equatable {
  final String runId;
  final String predictionId;
  final String engineId;
  final String cycleId;
  final String dataTimestamp;
  final double predictedRul;
  final String time;
  final String status;

  const HistoryEntity({
    required this.runId,
    required this.predictionId,
    required this.engineId,
    required this.cycleId,
    required this.dataTimestamp,
    required this.predictedRul,
    required this.time,
    required this.status,
  });

  @override
  List<Object> get props => [
    runId,
    predictionId,
    engineId,
    cycleId,
    dataTimestamp,
    predictedRul,
    time,
    status,
  ];
}

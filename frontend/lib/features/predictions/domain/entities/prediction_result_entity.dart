import 'package:equatable/equatable.dart';

/// Prediction result entity
class PredictionResultEntity extends Equatable {
  final int unit;
  final int cycle;
  final int inputRows;
  final int predictedRul;
  final List<ShapFeatureEntity> topFeatures;
  final String riskLevel;
  final String recommendation;
  final String predictionReport;
  final Map<String, double> healthProbabilities;

  const PredictionResultEntity({
    required this.unit,
    required this.cycle,
    required this.inputRows,
    required this.predictedRul,
    required this.topFeatures,
    required this.riskLevel,
    required this.recommendation,
    required this.predictionReport,
    required this.healthProbabilities,
  });

  @override
  List<Object> get props => [
    unit,
    cycle,
    inputRows,
    predictedRul,
    topFeatures,
    riskLevel,
    recommendation,
    predictionReport,
    healthProbabilities,
  ];
}

/// SHAP feature contribution entity
class ShapFeatureEntity extends Equatable {
  final String feature;
  final double shapValue;
  final double absShapValue;
  final double importancePercent;
  final String effect;

  const ShapFeatureEntity({
    required this.feature,
    required this.shapValue,
    required this.absShapValue,
    required this.importancePercent,
    required this.effect,
  });

  @override
  List<Object> get props => [
    feature,
    shapValue,
    absShapValue,
    importancePercent,
    effect,
  ];
}

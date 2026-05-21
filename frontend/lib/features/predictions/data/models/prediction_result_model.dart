import 'package:predection_desktop_app/features/predictions/domain/entities/prediction_result_entity.dart';

/// Prediction result data model
class PredictionResultModel extends PredictionResultEntity {
  const PredictionResultModel({
    required super.unit,
    required super.cycle,
    required super.inputRows,
    required super.predictedRul,
    required super.topFeatures,
    required super.riskLevel,
    required super.recommendation,
    required super.predictionReport,
    required super.healthProbabilities,
  });

  factory PredictionResultModel.fromJson(Map<String, dynamic> json) {
    try {
      final prediction = json['prediction'] as Map<String, dynamic>? ?? {};
      final report = json['report'] as Map<String, dynamic>? ?? {};

      final featuresData = prediction['top_feature_contributions'];
      final features = featuresData != null && featuresData is List
          ? featuresData.map((f) => ShapFeatureModel.fromJson(f)).toList()
          : <ShapFeatureModel>[];

      // Parse health probabilities
      final healthProbs =
          prediction['health_probabilities'] as Map<String, dynamic>? ?? {};
      final healthProbabilities = <String, double>{
        'Ok': _toDouble(
          healthProbs['Ok'] ??
              healthProbs['ok'] ??
              healthProbs['Normal'] ??
              healthProbs['normal'] ??
              0,
        ),
        'Watch': _toDouble(healthProbs['Watch'] ?? healthProbs['watch'] ?? 0),
        'Critical': _toDouble(
          healthProbs['Critical'] ?? healthProbs['critical'] ?? 0,
        ),
      };

      return PredictionResultModel(
        unit: prediction['unit'] as int? ?? 0,
        cycle: prediction['cycle'] as int? ?? 0,
        inputRows: prediction['input_rows'] as int? ?? 0,
        predictedRul: prediction['predicted_rul'] as int? ?? 0,
        topFeatures: features,
        riskLevel: report['risk_level'] as String? ?? 'unknown',
        recommendation: report['recommendation'] as String? ?? '',
        predictionReport:
            report['prediction_report'] as String? ??
            report['report'] as String? ??
            '',
        healthProbabilities: healthProbabilities,
      );
    } catch (e) {
      print('❌ Error parsing prediction result: $e');
      print('📥 JSON data: $json');
      rethrow;
    }
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  PredictionResultEntity toEntity() {
    return PredictionResultEntity(
      unit: unit,
      cycle: cycle,
      inputRows: inputRows,
      predictedRul: predictedRul,
      topFeatures: topFeatures,
      riskLevel: riskLevel,
      recommendation: recommendation,
      predictionReport: predictionReport,
      healthProbabilities: healthProbabilities,
    );
  }
}

/// SHAP feature model
class ShapFeatureModel extends ShapFeatureEntity {
  const ShapFeatureModel({
    required super.feature,
    required super.shapValue,
    required super.absShapValue,
    required super.importancePercent,
    required super.effect,
  });

  factory ShapFeatureModel.fromJson(Map<String, dynamic> json) {
    return ShapFeatureModel(
      feature: json['feature'] as String? ?? '',
      shapValue: PredictionResultModel._toDouble(json['shap_value']),
      absShapValue: PredictionResultModel._toDouble(json['abs_shap_value']),
      importancePercent: PredictionResultModel._toDouble(
        json['importance_percent'],
      ),
      effect: json['effect'] as String? ?? '',
    );
  }
}

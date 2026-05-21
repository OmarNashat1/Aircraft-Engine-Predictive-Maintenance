import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:predection_desktop_app/core/error/failures.dart';
import 'package:predection_desktop_app/features/predictions/domain/entities/prediction_result_entity.dart';

/// Prediction repository interface
abstract class PredictionRepository {
  Future<Either<Failure, PredictionResultEntity>> runPrediction({
    required File csvFile,
    Function(double)? onProgress,
  });
}

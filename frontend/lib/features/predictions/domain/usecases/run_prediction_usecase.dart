import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:predection_desktop_app/core/error/failures.dart';
import 'package:predection_desktop_app/features/predictions/domain/entities/prediction_result_entity.dart';
import 'package:predection_desktop_app/features/predictions/domain/repositories/prediction_repository.dart';

/// Use case to run prediction
@injectable
class RunPredictionUseCase {
  final PredictionRepository repository;

  RunPredictionUseCase(this.repository);

  Future<Either<Failure, PredictionResultEntity>> call({
    required File csvFile,
    Function(double)? onProgress,
  }) async {
    // Validate file exists
    if (!csvFile.existsSync()) {
      return const Left(ValidationFailure('File does not exist'));
    }

    // Validate file extension
    if (!csvFile.path.toLowerCase().endsWith('.csv')) {
      return const Left(ValidationFailure('File must be a CSV file'));
    }

    // Call repository
    return await repository.runPrediction(
      csvFile: csvFile,
      onProgress: onProgress,
    );
  }
}

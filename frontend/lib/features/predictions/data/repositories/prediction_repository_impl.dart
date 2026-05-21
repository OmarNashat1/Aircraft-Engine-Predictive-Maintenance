import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:predection_desktop_app/core/error/exceptions.dart';
import 'package:predection_desktop_app/core/error/failures.dart';
import 'package:predection_desktop_app/features/predictions/data/datasources/prediction_remote_datasource.dart';
import 'package:predection_desktop_app/features/predictions/domain/entities/prediction_result_entity.dart';
import 'package:predection_desktop_app/features/predictions/domain/repositories/prediction_repository.dart';

/// Implementation of PredictionRepository
@LazySingleton(as: PredictionRepository)
class PredictionRepositoryImpl implements PredictionRepository {
  final PredictionRemoteDataSource remoteDataSource;

  PredictionRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, PredictionResultEntity>> runPrediction({
    required File csvFile,
    Function(double)? onProgress,
  }) async {
    try {
      final model = await remoteDataSource.runPrediction(
        csvFile: csvFile,
        onProgress: onProgress,
      );
      return Right(model.toEntity());
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: ${e.toString()}'));
    }
  }
}

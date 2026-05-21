import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:predection_desktop_app/core/error/exceptions.dart';
import 'package:predection_desktop_app/core/error/failures.dart';
import 'package:predection_desktop_app/features/history/data/datasources/history_remote_datasource.dart';
import 'package:predection_desktop_app/features/history/domain/entities/history_entity.dart';
import 'package:predection_desktop_app/features/history/domain/repositories/history_repository.dart';

/// Implementation of HistoryRepository
@LazySingleton(as: HistoryRepository)
class HistoryRepositoryImpl implements HistoryRepository {
  final HistoryRemoteDataSource remoteDataSource;

  HistoryRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, List<HistoryEntity>>> getHistory() async {
    try {
      final models = await remoteDataSource.getHistory();
      return Right(models.map((m) => m.toEntity()).toList());
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: ${e.toString()}'));
    }
  }
}

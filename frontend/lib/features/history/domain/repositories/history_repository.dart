import 'package:dartz/dartz.dart';
import 'package:predection_desktop_app/core/error/failures.dart';
import 'package:predection_desktop_app/features/history/domain/entities/history_entity.dart';

/// History repository interface (Domain layer)
abstract class HistoryRepository {
  Future<Either<Failure, List<HistoryEntity>>> getHistory();
}

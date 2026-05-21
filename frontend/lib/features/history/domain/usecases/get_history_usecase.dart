import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:predection_desktop_app/core/error/failures.dart';
import 'package:predection_desktop_app/features/history/domain/entities/history_entity.dart';
import 'package:predection_desktop_app/features/history/domain/repositories/history_repository.dart';

/// Use case to get prediction history
@injectable
class GetHistoryUseCase {
  final HistoryRepository repository;

  GetHistoryUseCase(this.repository);

  Future<Either<Failure, List<HistoryEntity>>> call() async {
    return await repository.getHistory();
  }
}

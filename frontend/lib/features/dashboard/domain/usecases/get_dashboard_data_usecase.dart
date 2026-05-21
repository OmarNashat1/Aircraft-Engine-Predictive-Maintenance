import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:predection_desktop_app/core/error/failures.dart';
import 'package:predection_desktop_app/features/dashboard/domain/entities/dashboard_summary_entity.dart';
import 'package:predection_desktop_app/features/dashboard/domain/repositories/dashboard_repository.dart';

/// Use case to get dashboard summary
@injectable
class GetDashboardDataUseCase {
  final DashboardRepository repository;

  GetDashboardDataUseCase(this.repository);

  Future<Either<Failure, DashboardSummaryEntity>> call() async {
    return await repository.getDashboardSummary();
  }
}

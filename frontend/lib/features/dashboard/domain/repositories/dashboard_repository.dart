import 'package:dartz/dartz.dart';
import 'package:predection_desktop_app/core/error/failures.dart';
import 'package:predection_desktop_app/features/dashboard/domain/entities/dashboard_summary_entity.dart';

/// Dashboard repository interface (Domain layer)
abstract class DashboardRepository {
  Future<Either<Failure, DashboardSummaryEntity>> getDashboardSummary();
}

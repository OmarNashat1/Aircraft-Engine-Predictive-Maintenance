import 'package:equatable/equatable.dart';
import 'package:predection_desktop_app/features/dashboard/domain/entities/dashboard_summary_entity.dart';

/// Base dashboard state
abstract class DashboardState extends Equatable {
  const DashboardState();

  @override
  List<Object?> get props => [];
}

/// Initial state
class DashboardInitial extends DashboardState {}

/// Loading state
class DashboardLoading extends DashboardState {}

/// Loaded state
class DashboardLoaded extends DashboardState {
  final DashboardSummaryEntity summary;

  const DashboardLoaded(this.summary);

  @override
  List<Object> get props => [summary];
}

/// Error state
class DashboardError extends DashboardState {
  final String message;

  const DashboardError(this.message);

  @override
  List<Object> get props => [message];
}

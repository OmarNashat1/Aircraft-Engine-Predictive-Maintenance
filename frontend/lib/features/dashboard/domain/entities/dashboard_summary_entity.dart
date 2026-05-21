import 'package:equatable/equatable.dart';

/// Dashboard Summary domain entity
class DashboardSummaryEntity extends Equatable {
  final int okCount;
  final int watchCount;
  final int criticalCount;
  final int activeAlerts;

  const DashboardSummaryEntity({
    required this.okCount,
    required this.watchCount,
    required this.criticalCount,
    required this.activeAlerts,
  });

  int get totalEngines => okCount + watchCount + criticalCount;

  @override
  List<Object> get props => [okCount, watchCount, criticalCount, activeAlerts];
}

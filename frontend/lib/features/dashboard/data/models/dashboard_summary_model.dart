import 'package:predection_desktop_app/features/dashboard/domain/entities/dashboard_summary_entity.dart';

/// Dashboard Summary data model with JSON serialization
class DashboardSummaryModel extends DashboardSummaryEntity {
  const DashboardSummaryModel({
    required super.okCount,
    required super.watchCount,
    required super.criticalCount,
    required super.activeAlerts,
  });

  factory DashboardSummaryModel.fromJson(Map<String, dynamic> json) {
    final fleetHealth = json['fleet_health'] as Map<String, dynamic>;

    return DashboardSummaryModel(
      okCount: fleetHealth['ok'] ?? 0,
      watchCount: fleetHealth['watch'] ?? 0,
      criticalCount: fleetHealth['critical'] ?? 0,
      activeAlerts: json['active_alerts'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fleet_health': {
        'ok': okCount,
        'watch': watchCount,
        'critical': criticalCount,
      },
      'active_alerts': activeAlerts,
    };
  }

  DashboardSummaryEntity toEntity() {
    return DashboardSummaryEntity(
      okCount: okCount,
      watchCount: watchCount,
      criticalCount: criticalCount,
      activeAlerts: activeAlerts,
    );
  }
}

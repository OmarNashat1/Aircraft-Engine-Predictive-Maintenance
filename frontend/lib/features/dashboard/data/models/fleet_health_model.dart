import 'package:predection_desktop_app/features/dashboard/domain/entities/fleet_health_entity.dart';

/// Fleet Health data model with JSON serialization
class FleetHealthModel extends FleetHealthEntity {
  const FleetHealthModel({
    required super.okCount,
    required super.watchCount,
    required super.criticalCount,
    required super.totalEngines,
  });

  factory FleetHealthModel.fromJson(Map<String, dynamic> json) {
    return FleetHealthModel(
      okCount: json['ok_count'] ?? json['okCount'] ?? 0,
      watchCount: json['watch_count'] ?? json['watchCount'] ?? 0,
      criticalCount: json['critical_count'] ?? json['criticalCount'] ?? 0,
      totalEngines: json['total_engines'] ?? json['totalEngines'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ok_count': okCount,
      'watch_count': watchCount,
      'critical_count': criticalCount,
      'total_engines': totalEngines,
    };
  }

  FleetHealthEntity toEntity() {
    return FleetHealthEntity(
      okCount: okCount,
      watchCount: watchCount,
      criticalCount: criticalCount,
      totalEngines: totalEngines,
    );
  }
}

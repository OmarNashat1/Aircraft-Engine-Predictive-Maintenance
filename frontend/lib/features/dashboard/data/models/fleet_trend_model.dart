import 'package:predection_desktop_app/features/dashboard/domain/entities/fleet_trend_entity.dart';

/// Fleet Trend data model with JSON serialization
class FleetTrendModel extends FleetTrendEntity {
  const FleetTrendModel({
    required super.dayLabel,
    required super.avgEgt,
    required super.vibration,
    required super.avgRul,
  });

  factory FleetTrendModel.fromJson(Map<String, dynamic> json) {
    return FleetTrendModel(
      dayLabel:
          json['day_label']?.toString() ?? json['dayLabel']?.toString() ?? '',
      avgEgt: (json['avg_egt'] ?? json['avgEgt'] ?? 0).toDouble(),
      vibration: (json['vibration'] ?? 0).toDouble(),
      avgRul: (json['avg_rul'] ?? json['avgRul'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'day_label': dayLabel,
      'avg_egt': avgEgt,
      'vibration': vibration,
      'avg_rul': avgRul,
    };
  }

  FleetTrendEntity toEntity() {
    return FleetTrendEntity(
      dayLabel: dayLabel,
      avgEgt: avgEgt,
      vibration: vibration,
      avgRul: avgRul,
    );
  }
}

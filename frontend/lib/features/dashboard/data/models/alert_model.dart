import 'package:predection_desktop_app/features/dashboard/domain/entities/alert_entity.dart';

/// Alert data model with JSON serialization
class AlertModel extends AlertEntity {
  const AlertModel({
    required super.alertId,
    required super.engineId,
    required super.alertLevel,
    required super.message,
    required super.rule,
    required super.createdAt,
    super.isResolved,
    super.isEscalated,
    super.isOverdue,
  });

  factory AlertModel.fromJson(Map<String, dynamic> json) {
    return AlertModel(
      alertId: json['alert_id']?.toString() ?? json['id']?.toString() ?? '',
      engineId:
          json['engine_id']?.toString() ?? json['engineId']?.toString() ?? '',
      alertLevel:
          json['alert_level'] ??
          json['alertLevel'] ??
          json['severity'] ??
          'watch',
      message: json['message'] ?? '',
      rule: json['rule'] ?? json['alert_type'] ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      isResolved: json['is_resolved'] ?? json['isResolved'] ?? false,
      isEscalated: json['is_escalated'] ?? json['isEscalated'] ?? false,
      isOverdue: json['is_overdue'] ?? json['isOverdue'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'alert_id': alertId,
      'engine_id': engineId,
      'alert_level': alertLevel,
      'message': message,
      'rule': rule,
      'created_at': createdAt.toIso8601String(),
      'is_resolved': isResolved,
      'is_escalated': isEscalated,
      'is_overdue': isOverdue,
    };
  }

  AlertEntity toEntity() {
    return AlertEntity(
      alertId: alertId,
      engineId: engineId,
      alertLevel: alertLevel,
      message: message,
      rule: rule,
      createdAt: createdAt,
      isResolved: isResolved,
      isEscalated: isEscalated,
      isOverdue: isOverdue,
    );
  }
}

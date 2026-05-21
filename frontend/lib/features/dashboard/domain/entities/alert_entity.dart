import 'package:equatable/equatable.dart';

/// Alert domain entity
class AlertEntity extends Equatable {
  final String alertId;
  final String engineId;
  final String alertLevel; // 'critical', 'watch', 'acknowledged'
  final String message;
  final String rule;
  final DateTime createdAt;
  final bool isResolved;
  final bool isEscalated;
  final bool isOverdue;

  const AlertEntity({
    required this.alertId,
    required this.engineId,
    required this.alertLevel,
    required this.message,
    required this.rule,
    required this.createdAt,
    this.isResolved = false,
    this.isEscalated = false,
    this.isOverdue = false,
  });

  @override
  List<Object> get props => [
    alertId,
    engineId,
    alertLevel,
    message,
    rule,
    createdAt,
    isResolved,
    isEscalated,
    isOverdue,
  ];
}

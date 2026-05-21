import 'package:equatable/equatable.dart';

/// Fleet Health domain entity
class FleetHealthEntity extends Equatable {
  final int okCount;
  final int watchCount;
  final int criticalCount;
  final int totalEngines;

  const FleetHealthEntity({
    required this.okCount,
    required this.watchCount,
    required this.criticalCount,
    required this.totalEngines,
  });

  @override
  List<Object> get props => [okCount, watchCount, criticalCount, totalEngines];
}

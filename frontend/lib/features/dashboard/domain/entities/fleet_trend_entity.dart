import 'package:equatable/equatable.dart';

/// Fleet Trend domain entity (for chart data)
class FleetTrendEntity extends Equatable {
  final String dayLabel; // e.g., "Day 1", "Day 5"
  final double avgEgt; // Average Exhaust Gas Temperature
  final double vibration; // Vibration level
  final double avgRul; // Average Remaining Useful Life

  const FleetTrendEntity({
    required this.dayLabel,
    required this.avgEgt,
    required this.vibration,
    required this.avgRul,
  });

  @override
  List<Object> get props => [dayLabel, avgEgt, vibration, avgRul];
}

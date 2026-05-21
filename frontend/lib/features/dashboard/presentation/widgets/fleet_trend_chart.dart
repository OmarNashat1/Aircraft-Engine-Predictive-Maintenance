import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:predection_desktop_app/features/dashboard/domain/entities/fleet_trend_entity.dart';

class FleetTrendChart extends StatelessWidget {
  final List<FleetTrendEntity> trendData;

  const FleetTrendChart({super.key, required this.trendData});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fleet Trend - Last 30 Days',
            style: TextStyle(
              color: Color(0xFFE6EDF3),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          if (trendData.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Text(
                  'No trend data available',
                  style: TextStyle(color: Color(0xFF8B949E), fontSize: 14),
                ),
              ),
            )
          else
            SizedBox(
              height: 300,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: 100,
                    verticalInterval: 5,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: const Color(0xFF30363D),
                        strokeWidth: 1,
                      );
                    },
                    getDrawingVerticalLine: (value) {
                      return FlLine(
                        color: const Color(0xFF30363D),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: 5,
                        getTitlesWidget: (double value, TitleMeta meta) {
                          if (value.toInt() >= 0 &&
                              value.toInt() < trendData.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                trendData[value.toInt()].dayLabel,
                                style: const TextStyle(
                                  color: Color(0xFF8B949E),
                                  fontSize: 12,
                                ),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 200,
                        reservedSize: 42,
                        getTitlesWidget: (double value, TitleMeta meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(
                              color: Color(0xFF8B949E),
                              fontSize: 12,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  minX: 0,
                  maxX: (trendData.length - 1).toDouble(),
                  minY: 0,
                  maxY: 800,
                  lineBarsData: [
                    // Avg EGT Line (Red)
                    LineChartBarData(
                      spots: trendData.asMap().entries.map((entry) {
                        return FlSpot(entry.key.toDouble(), entry.value.avgEgt);
                      }).toList(),
                      isCurved: true,
                      color: const Color(0xFFDA3633),
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                    // Vibration Line (Orange)
                    LineChartBarData(
                      spots: trendData.asMap().entries.map((entry) {
                        return FlSpot(
                          entry.key.toDouble(),
                          entry.value.vibration,
                        );
                      }).toList(),
                      isCurved: true,
                      color: const Color(0xFFD29922),
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                    // RUL Line (Blue)
                    LineChartBarData(
                      spots: trendData.asMap().entries.map((entry) {
                        return FlSpot(entry.key.toDouble(), entry.value.avgRul);
                      }).toList(),
                      isCurved: true,
                      color: const Color(0xFF1E6FD9),
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem('Avg EGT (°C)', const Color(0xFFDA3633)),
              const SizedBox(width: 24),
              _buildLegendItem('Vibration (mm/s)', const Color(0xFFD29922)),
              const SizedBox(width: 24),
              _buildLegendItem('RUL (cycles)', const Color(0xFF1E6FD9)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
        ),
      ],
    );
  }
}

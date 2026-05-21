import 'dart:math';

import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:predection_desktop_app/shared/layouts/main_layout.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const MainLayout(
      currentRoute: '/dashboard',
      child: _DashboardContent(),
    );
  }
}

class _DashboardContent extends StatefulWidget {
  const _DashboardContent();

  @override
  State<_DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<_DashboardContent> {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'http://127.0.0.1:8000',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  bool _isLoading = true;
  String? _errorMessage;

  _DashboardSummary _summary = const _DashboardSummary(
    ok: 0,
    watch: 0,
    critical: 0,
    activeAlerts: 0,
  );

  List<_FleetTrendPoint> _trendPoints = [];
  List<_AlertRow> _recentAlerts = [];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }


  void _safeSetState(VoidCallback update) {
    if (!mounted) return;
    setState(update);
  }

  Future<void> _loadDashboard() async {
    _safeSetState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Future.wait([
        _loadSummary(),
        _loadFleetTrend(),
        _loadRecentAlerts(),
      ]);
    } catch (e) {
      _safeSetState(() {
        _errorMessage = 'Failed to load dashboard data: $e';
      });
    } finally {
      _safeSetState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSummary() async {
    final response = await _dio.get('/dashboard-summary');
    final data = response.data;

    if (data is! Map) {
      throw Exception('Invalid dashboard-summary response.');
    }

    final map = Map<String, dynamic>.from(data);

    if (map['error'] != null) {
      throw Exception(map['error']);
    }

    final fleetHealth = Map<String, dynamic>.from(
      (map['fleet_health'] as Map?) ?? {},
    );

    _safeSetState(() {
      _summary = _DashboardSummary(
        ok: int.tryParse(fleetHealth['ok']?.toString() ?? '') ?? 0,
        watch: int.tryParse(fleetHealth['watch']?.toString() ?? '') ?? 0,
        critical: int.tryParse(fleetHealth['critical']?.toString() ?? '') ?? 0,
        activeAlerts: int.tryParse(map['active_alerts']?.toString() ?? '') ?? 0,
      );
    });
  }

  Future<void> _loadFleetTrend() async {
    final response = await _dio.get(
      '/dashboard/fleet-health-trend',
      queryParameters: {
        'days': 30,
      },
    );

    final data = response.data;

    if (data is! Map) {
      throw Exception('Invalid fleet-health-trend response.');
    }

    final map = Map<String, dynamic>.from(data);

    if (map['error'] != null) {
      throw Exception(map['error']);
    }

    final series = map['series'];

    if (series is! List) {
      _safeSetState(() {
        _trendPoints = [];
      });
      return;
    }

    final points = <_FleetTrendPoint>[];

    for (int i = 0; i < series.length; i++) {
      final item = series[i];

      if (item is! Map) {
        continue;
      }

      final row = Map<String, dynamic>.from(item);

      points.add(
        _FleetTrendPoint(
          index: i,
          date: row['date']?.toString() ?? '',
          ok: int.tryParse(row['ok']?.toString() ?? '') ?? 0,
          watch: int.tryParse(row['watch']?.toString() ?? '') ?? 0,
          critical: int.tryParse(row['critical']?.toString() ?? '') ?? 0,
          total: int.tryParse(row['total']?.toString() ?? '') ?? 0,
        ),
      );
    }

    _safeSetState(() {
      _trendPoints = points;
    });
  }

  Future<void> _loadRecentAlerts() async {
    final response = await _dio.get('/alerts');
    final data = response.data;

    if (data is Map && data['error'] != null) {
      throw Exception(data['error']);
    }

    if (data is! List) {
      _safeSetState(() {
        _recentAlerts = [];
      });
      return;
    }

    final alerts = <_AlertRow>[];

    for (final item in data) {
      if (item is! Map) {
        continue;
      }

      final map = Map<String, dynamic>.from(item);

      alerts.add(
        _AlertRow(
          alertId: int.tryParse(map['alert_id']?.toString() ?? '') ?? 0,
          predictionId:
              int.tryParse(map['prediction_id']?.toString() ?? '') ?? 0,
          level: _normalizeAlertLevel(map['alert_level']),
          message: map['message']?.toString() ?? 'No alert message',
          createdAt: map['created_at']?.toString() ?? '',
          isResolved: _parseBool(map['is_resolved']),
        ),
      );
    }

    alerts.sort((a, b) {
      final aTime = DateTime.tryParse(a.createdAt);
      final bTime = DateTime.tryParse(b.createdAt);

      if (aTime == null || bTime == null) {
        return b.alertId.compareTo(a.alertId);
      }

      return bTime.compareTo(aTime);
    });

    _safeSetState(() {
      _recentAlerts = alerts.take(3).toList();
    });
  }

  String _normalizeAlertLevel(dynamic value) {
    final level = value?.toString().toLowerCase().trim() ?? '';

    if (level == 'critical' || level == 'high') {
      return 'critical';
    }

    if (level == 'watch' || level == 'warning' || level == 'medium') {
      return 'watch';
    }

    if (level == 'ok' || level == 'low') {
      return 'ok';
    }

    return level.isEmpty ? 'watch' : level;
  }

  bool _parseBool(dynamic value) {
    if (value is bool) {
      return value;
    }

    final text = value?.toString().toLowerCase().trim() ?? '';
    return text == 'true' || text == '1' || text == 'yes';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              _buildErrorBox(_errorMessage!),
            ],
            const SizedBox(height: 24),
            _buildTopCards(),
            const SizedBox(height: 24),
            _buildRecentAlertsCard(context),
            const SizedBox(height: 24),
            _buildFleetTrendCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Predictive Maintenance Dashboard',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Real-time fleet health, alerts, and 30-day status trend',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _loadDashboard,
          tooltip: 'Refresh dashboard',
          icon: const Icon(
            Icons.refresh_rounded,
            color: Color(0xFF2563EB),
          ),
        ),
      ],
    );
  }

  Widget _buildTopCards() {
    return Row(
      children: [
        Expanded(
          child: _DashboardMetricCard(
            title: 'Fleet Health',
            value: '${_summary.ok} / ${_summary.watch} / ${_summary.critical}',
            subtitle: 'OK / Watch / Critical',
            icon: Icons.monitor_heart_outlined,
            accentColor: _summary.critical > 0
                ? const Color(0xFFE11D48)
                : _summary.watch > 0
                    ? const Color(0xFFEAB308)
                    : const Color(0xFF22C55E),
            footer: Row(
              children: [
                _buildMiniStatusDot(const Color(0xFF22C55E), 'OK'),
                const SizedBox(width: 12),
                _buildMiniStatusDot(const Color(0xFFEAB308), 'Watch'),
                const SizedBox(width: 12),
                _buildMiniStatusDot(const Color(0xFFE11D48), 'Critical'),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _DashboardMetricCard(
            title: 'Active Alerts',
            value: _summary.activeAlerts.toString(),
            subtitle: 'Unresolved maintenance alerts',
            icon: Icons.notifications_active_outlined,
            accentColor: _summary.activeAlerts > 0
                ? const Color(0xFFE11D48)
                : const Color(0xFF22C55E),
            footer: Text(
              _summary.activeAlerts > 0
                  ? 'Requires maintenance review'
                  : 'No active unresolved alerts',
              style: TextStyle(
                fontSize: 12,
                color: _summary.activeAlerts > 0
                    ? const Color(0xFFE11D48)
                    : const Color(0xFF22C55E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStatusDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildRecentAlertsCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent Alerts',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/alerts');
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF111827),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (_recentAlerts.isEmpty)
            _buildEmptyState(
              icon: Icons.notifications_none_outlined,
              title: 'No recent alerts',
              message: 'New maintenance alerts will appear here.',
            )
          else
            Column(
              children: [
                for (int i = 0; i < _recentAlerts.length; i++) ...[
                  _AlertTile(alert: _recentAlerts[i]),
                  if (i != _recentAlerts.length - 1)
                    const SizedBox(height: 12),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFleetTrendCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fleet Trend - Last 30 Days',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Daily fleet health snapshot by latest engine status',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 22),
          if (_trendPoints.isEmpty)
            _buildEmptyState(
              icon: Icons.show_chart_rounded,
              title: 'No trend data available',
              message: 'Fleet trend appears after prediction rows exist.',
            )
          else
            Column(
              children: [
                SizedBox(
                  height: 320,
                  child: LineChart(_buildFleetTrendChartData()),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 10,
                  children: const [
                    _ChartLegendDot(
                      color: Color(0xFF22C55E),
                      label: 'OK',
                    ),
                    _ChartLegendDot(
                      color: Color(0xFFEAB308),
                      label: 'Watch',
                    ),
                    _ChartLegendDot(
                      color: Color(0xFFE11D48),
                      label: 'Critical',
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  LineChartData _buildFleetTrendChartData() {
    final okSpots = <FlSpot>[];
    final watchSpots = <FlSpot>[];
    final criticalSpots = <FlSpot>[];

    for (final point in _trendPoints) {
      final x = point.index.toDouble();

      okSpots.add(FlSpot(x, point.ok.toDouble()));
      watchSpots.add(FlSpot(x, point.watch.toDouble()));
      criticalSpots.add(FlSpot(x, point.critical.toDouble()));
    }

    final maxYValue = _trendPoints.fold<int>(
      0,
      (currentMax, point) => max(
        currentMax,
        max(point.ok, max(point.watch, point.critical)),
      ),
    );

    final maxY = max(1, maxYValue).toDouble();
    final paddedMaxY = maxY + 0.25;
    const yInterval = 1.0;

    final maxX = max(0, _trendPoints.length - 1).toDouble();
    final xInterval = _trendPoints.length <= 6
        ? 1.0
        : max(1.0, ((_trendPoints.length - 1) / 5).roundToDouble());

    return LineChartData(
      minX: 0,
      maxX: maxX,
      minY: 0,
      maxY: paddedMaxY,
      lineTouchData: LineTouchData(
        enabled: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) {
            return spots.map((spot) {
              final index = spot.x
                  .round()
                  .clamp(0, _trendPoints.length - 1)
                  .toInt();

              final point = _trendPoints[index];

              final label = switch (spot.barIndex) {
                0 => 'OK',
                1 => 'Watch',
                2 => 'Critical',
                _ => 'Count',
              };

              final color = switch (spot.barIndex) {
                0 => const Color(0xFF22C55E),
                1 => const Color(0xFFEAB308),
                2 => const Color(0xFFE11D48),
                _ => const Color(0xFF111827),
              };

              return LineTooltipItem(
                '${_formatDate(point.date)}\n$label: ${spot.y.toInt()}',
                TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              );
            }).toList();
          },
        ),
      ),
      lineBarsData: [
        _buildTrendBar(
          spots: okSpots,
          color: const Color(0xFF22C55E),
        ),
        _buildTrendBar(
          spots: watchSpots,
          color: const Color(0xFFEAB308),
        ),
        _buildTrendBar(
          spots: criticalSpots,
          color: const Color(0xFFE11D48),
        ),
      ],
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: yInterval,
        verticalInterval: xInterval,
        getDrawingHorizontalLine: (_) => FlLine(
          color: const Color(0xFFE5E7EB),
          strokeWidth: 1,
          dashArray: [4, 4],
        ),
        getDrawingVerticalLine: (_) => FlLine(
          color: const Color(0xFFE5E7EB),
          strokeWidth: 1,
          dashArray: [4, 4],
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: xInterval,
            reservedSize: 38,
            getTitlesWidget: (value, meta) {
              final index = value.round();

              if (index < 0 || index >= _trendPoints.length) {
                return const SizedBox.shrink();
              }

              if ((value - index).abs() > 0.01) {
                return const SizedBox.shrink();
              }

              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _formatDate(_trendPoints[index].date),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: yInterval,
            reservedSize: 48,
            getTitlesWidget: (value, meta) {
              if (value % 1 != 0) {
                return const SizedBox.shrink();
              }

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  value.toInt().toString(),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  LineChartBarData _buildTrendBar({
    required List<FlSpot> spots,
    required Color color,
  }) {
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: color,
      barWidth: 2.6,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: spots.length <= 10,
      ),
      belowBarData: BarAreaData(
        show: false,
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(34),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: const Color(0xFF94A3B8),
            size: 42,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748B),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFDC2626)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF991B1B)),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE5E7EB)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.025),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  String _formatDate(String value) {
    final parsed = DateTime.tryParse(value);

    if (parsed == null) {
      return value;
    }

    return '${parsed.month}/${parsed.day}';
  }
}

class _DashboardSummary {
  final int ok;
  final int watch;
  final int critical;
  final int activeAlerts;

  const _DashboardSummary({
    required this.ok,
    required this.watch,
    required this.critical,
    required this.activeAlerts,
  });
}

class _FleetTrendPoint {
  final int index;
  final String date;
  final int ok;
  final int watch;
  final int critical;
  final int total;

  const _FleetTrendPoint({
    required this.index,
    required this.date,
    required this.ok,
    required this.watch,
    required this.critical,
    required this.total,
  });
}

class _AlertRow {
  final int alertId;
  final int predictionId;
  final String level;
  final String message;
  final String createdAt;
  final bool isResolved;

  const _AlertRow({
    required this.alertId,
    required this.predictionId,
    required this.level,
    required this.message,
    required this.createdAt,
    required this.isResolved,
  });

  Color get levelColor {
    if (isResolved) {
      return const Color(0xFF94A3B8);
    }

    switch (level) {
      case 'critical':
        return const Color(0xFFE11D48);
      case 'watch':
        return const Color(0xFFEAB308);
      case 'ok':
        return const Color(0xFF22C55E);
      default:
        return const Color(0xFF64748B);
    }
  }

  String get statusText {
    return isResolved ? 'resolved' : 'open';
  }
}

class _DashboardMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final Widget footer;

  const _DashboardMetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 170,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: accentColor,
              size: 23,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 32,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
                const Spacer(),
                footer,
              ],
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  final _AlertRow alert;

  const _AlertTile({
    required this.alert,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(
            alert.level == 'critical'
                ? Icons.warning_amber_rounded
                : Icons.info_outline_rounded,
            color: alert.levelColor,
            size: 22,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Prediction #${alert.predictionId}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: alert.levelColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        alert.statusText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  alert.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alert.createdAt,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            onPressed: () {
              if (alert.predictionId > 0) {
                Navigator.of(context).pushNamed(
                  '/results/${alert.predictionId}',
                );
                return;
              }

              Navigator.of(context).pushNamed(
                '/alerts',
                arguments: {'alert_id': alert.alertId},
              );
            },
            icon: const Icon(
              Icons.visibility_outlined,
              size: 18,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartLegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _ChartLegendDot({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF334155),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
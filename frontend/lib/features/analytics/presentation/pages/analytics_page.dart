import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:predection_desktop_app/shared/layouts/main_layout.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final _api = _AnalyticsApi();

  bool _isLoading = true;
  bool _isRefreshingSensors = false;
  String? _error;

  List<FleetEngine> _engines = [];
  FleetSummary _summary = FleetSummary.empty();
  MonthPredictionSummary _monthSummary = MonthPredictionSummary.empty();
  FilterOptions _filterOptions = FilterOptions.empty();
  SensorGroupsResponse? _sensorGroups;

  int? _selectedEngineId;
  int? _selectedCycleId;
  String _selectedGroup = 'temperature';
  String? _selectedSensor;

  @override
  void initState() {
    super.initState();
    unawaited(_loadInitialData());
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait<dynamic>([
        _api.fetchEngines(),
        _api.fetchFleetSummary(),
        _api.fetchMonthPredictionSummary(),
        _api.fetchFilterOptions(),
      ]);

      final engines = results[0] as List<FleetEngine>;
      final summary = results[1] as FleetSummary;
      final monthSummary = results[2] as MonthPredictionSummary;
      final filterOptions = results[3] as FilterOptions;

      final initialEngine = filterOptions.engines.isNotEmpty
          ? filterOptions.engines.first
          : (engines.isNotEmpty ? engines.first.engineId : null);
      final initialCycles = initialEngine == null
          ? filterOptions.cycles
          : filterOptions.cyclesForEngine(initialEngine);
      final initialCycle = initialCycles.isNotEmpty
          ? initialCycles.last
          : (engines.isNotEmpty ? engines.first.cycleId : null);

      if (!mounted) return;
      setState(() {
        _engines = engines;
        _summary = summary;
        _monthSummary = monthSummary;
        _filterOptions = filterOptions;
        _selectedEngineId = initialEngine;
        _selectedCycleId = initialCycle;
        _isLoading = false;
      });

      await _loadSensorGroups();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Unable to load analytics data. $e';
      });
    }
  }

  Future<void> _loadSensorGroups() async {
    final engineId = _selectedEngineId;
    final cycleId = _selectedCycleId;

    if (engineId == null || cycleId == null) {
      setState(() {
        _sensorGroups = null;
      });
      return;
    }

    setState(() {
      _isRefreshingSensors = true;
    });

    try {
      final sensorGroups = await _api.fetchSensorGroups(
        engineId: engineId,
        cycleId: cycleId,
      );

      if (!mounted) return;
      setState(() {
        _sensorGroups = sensorGroups;
        _isRefreshingSensors = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sensorGroups = null;
        _isRefreshingSensors = false;
      });
    }
  }

  List<FleetEngine> get _visibleEngines {
    final sorted = [..._engines]
      ..sort((a, b) {
        final statusCompare = _statusSort(a.status).compareTo(_statusSort(b.status));
        if (statusCompare != 0) return statusCompare;
        return a.engineId.compareTo(b.engineId);
      });

    return sorted;
  }

  int _statusSort(String status) {
    switch (normalizeStatus(status)) {
      case EngineStatus.critical:
        return 0;
      case EngineStatus.watch:
        return 1;
      case EngineStatus.ok:
        return 2;
      case EngineStatus.unknown:
        return 3;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      currentRoute: '/analytics',
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const _CenteredCard(
        icon: Icons.analytics_outlined,
        title: 'Loading analytics',
        message: 'Preparing fleet health and sensor trend data...',
        showProgress: true,
      );
    }

    if (_error != null) {
      return _CenteredCard(
        icon: Icons.error_outline_rounded,
        title: 'Unable to load analytics',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _loadInitialData,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      color: AppPalette.blue,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeading(
              title: 'Analytics',
              subtitle: 'Fleet health overview, RUL indicators, and sensor trend analysis',
              trailing: IconButton(
                tooltip: 'Refresh analytics',
                onPressed: _loadInitialData,
                icon: const Icon(Icons.refresh_rounded),
                color: AppPalette.blue,
              ),
            ),
            const SizedBox(height: 22),
            _MetricCardsRow(
              summary: _summary,
              monthSummary: _monthSummary,
              engineCount: _engines.length,
            ),
            const SizedBox(height: 22),
            _FleetHealthOverviewCard(engines: _visibleEngines),
            const SizedBox(height: 22),
            _SensorTrendsCard(
              filterOptions: _filterOptions,
              selectedEngineId: _selectedEngineId,
              selectedCycleId: _selectedCycleId,
              selectedGroup: _selectedGroup,
              selectedSensor: _selectedSensor,
              sensorGroups: _sensorGroups,
              isRefreshing: _isRefreshingSensors,
              onEngineChanged: (value) {
                final cycles = value == null
                    ? <int>[]
                    : _filterOptions.cyclesForEngine(value);
                setState(() {
                  _selectedEngineId = value;
                  _selectedCycleId = cycles.isNotEmpty ? cycles.last : null;
                  _sensorGroups = null;
                });
                unawaited(_loadSensorGroups());
              },
              onCycleChanged: (value) {
                setState(() => _selectedCycleId = value);
                unawaited(_loadSensorGroups());
              },
              onGroupChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedGroup = value;
                  _selectedSensor = null;
                });
              },
              onSensorChanged: (value) {
                setState(() {
                  _selectedSensor = value == '__all__' ? null : value;
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.pageTitle),
              const SizedBox(height: 8),
              Text(subtitle, style: AppText.subtitle),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _MetricCardsRow extends StatelessWidget {
  const _MetricCardsRow({
    required this.summary,
    required this.monthSummary,
    required this.engineCount,
  });

  final FleetSummary summary;
  final MonthPredictionSummary monthSummary;
  final int engineCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 950;
        final cards = [
          _MetricCard(
            title: 'Fleet Health',
            value: '${summary.ok} / ${summary.watch} / ${summary.critical}',
            subtitle: 'OK / Watch / Critical',
            icon: Icons.monitor_heart_outlined,
            accent: AppPalette.green,
          ),
          _MetricCard(
            title: 'Active Alerts',
            value: '${summary.activeAlerts}',
            subtitle: 'Unresolved maintenance alerts',
            icon: Icons.notifications_active_outlined,
            accent: summary.activeAlerts > 0 ? AppPalette.red : AppPalette.green,
          ),
          _MetricCard(
            title: 'Predictions This Month',
            value: '${monthSummary.predictionsThisMonth}',
            subtitle: '${monthSummary.enginesThisMonth} engines analyzed',
            icon: Icons.trending_up_rounded,
            accent: AppPalette.blue,
          ),
          _MetricCard(
            title: 'Engines Tracked',
            value: '$engineCount',
            subtitle: 'Available in current fleet data',
            icon: Icons.precision_manufacturing_outlined,
            accent: AppPalette.purple,
          ),
        ];

        if (compact) {
          return Column(
            children: cards
                .map((card) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: card,
                    ))
                .toList(),
          );
        }

        return Row(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              Expanded(child: cards[i]),
              if (i != cards.length - 1) const SizedBox(width: 16),
            ],
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.metricTitle),
                const SizedBox(height: 8),
                Text(value, style: AppText.metricValue),
                const SizedBox(height: 6),
                Text(subtitle, style: AppText.subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FleetHealthOverviewCard extends StatelessWidget {
  const _FleetHealthOverviewCard({required this.engines});

  final List<FleetEngine> engines;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Fleet Health Overview', style: AppText.sectionTitle),
                    const SizedBox(height: 10),
                    Text(
                      'Current RUL and status for all engines in the fleet',
                      style: AppText.subtitle,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppPalette.inputFill,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppPalette.borderSoft),
                ),
                child: Text(
                  '${engines.length} engines',
                  style: AppText.badge.copyWith(color: AppPalette.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          if (engines.isEmpty)
            const _EmptyState(
              icon: Icons.precision_manufacturing_outlined,
              title: 'No engine data available',
              message: 'Run a prediction first to populate fleet health analytics.',
            )
          else
            _FleetTable(engines: engines),
        ],
      ),
    );
  }
}

class _FleetTable extends StatelessWidget {
  const _FleetTable({required this.engines});

  final List<FleetEngine> engines;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _FleetTableHeader(),
        for (final engine in engines) _FleetTableRow(engine: engine),
      ],
    );
  }
}

class _FleetTableHeader extends StatelessWidget {
  const _FleetTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppPalette.borderSoft)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('Engine ID', style: AppText.tableHeader)),
          Expanded(flex: 2, child: Text('Predicted RUL', style: AppText.tableHeader)),
          Expanded(flex: 2, child: Text('Status', style: AppText.tableHeader)),
          Expanded(flex: 3, child: Text('Health Indicator', style: AppText.tableHeader)),
        ],
      ),
    );
  }
}

class _FleetTableRow extends StatelessWidget {
  const _FleetTableRow({required this.engine});

  final FleetEngine engine;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppPalette.borderSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              engine.displayEngineId,
              style: AppText.tableBody.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('${engine.rul.round()} cycles', style: AppText.tableBody),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(status: normalizeStatus(engine.status)),
            ),
          ),
          Expanded(
            flex: 3,
            child: RulHealthIndicatorBar(
              rul: engine.rul,
              width: 270,
              height: 7,
            ),
          ),
        ],
      ),
    );
  }
}

class RulHealthIndicatorBar extends StatefulWidget {
  const RulHealthIndicatorBar({
    super.key,
    required this.rul,
    this.width = 260,
    this.height = 7,
  });

  final num rul;
  final double width;
  final double height;

  static const double maxRul = 99.0;

  @override
  State<RulHealthIndicatorBar> createState() => _RulHealthIndicatorBarState();
}

class _RulHealthIndicatorBarState extends State<RulHealthIndicatorBar> {
  bool _hovering = false;

  double get _safeRul => widget.rul.toDouble().clamp(0.0, RulHealthIndicatorBar.maxRul).toDouble();

  double get _fillFraction => (_safeRul / RulHealthIndicatorBar.maxRul).clamp(0.0, 1.0).toDouble();

  int get _displayPercent => _safeRul.round().clamp(0, 99).toInt();

  EngineStatus get _status {
    if (_safeRul <= 20) return EngineStatus.critical;
    if (_safeRul <= 40) return EngineStatus.watch;
    return EngineStatus.ok;
  }

  Color get _color => statusColor(_status);

  String get _statusText => statusDisplayName(_status);

  String get _rangeText {
    switch (_status) {
      case EngineStatus.critical:
        return 'Critical range: 20 cycles and below';
      case EngineStatus.watch:
        return 'Watch range: above 20 to 40 cycles';
      case EngineStatus.ok:
        return 'OK range: above 40 cycles';
      case EngineStatus.unknown:
        return 'Unknown range';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tooltipMessage = [
      'RUL: ${_safeRul.round()} cycles',
      'Status: $_statusText',
      'Bar: $_displayPercent%',
      _rangeText,
    ].join('\n');

    return Tooltip(
      message: tooltipMessage,
      waitDuration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: AppPalette.textPrimary,
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: AppText.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          width: widget.width,
          height: _hovering ? widget.height + 3 : widget.height,
          decoration: BoxDecoration(
            color: AppPalette.track,
            borderRadius: BorderRadius.circular(999),
            boxShadow: _hovering
                ? [
                    BoxShadow(
                      color: _color.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.centerLeft,
          clipBehavior: Clip.hardEdge,
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: _fillFraction,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final EngineStatus status;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        statusDisplayName(status).toLowerCase(),
        style: AppText.badge.copyWith(color: Colors.white),
      ),
    );
  }
}

class _SensorTrendsCard extends StatelessWidget {
  const _SensorTrendsCard({
    required this.filterOptions,
    required this.selectedEngineId,
    required this.selectedCycleId,
    required this.selectedGroup,
    required this.selectedSensor,
    required this.sensorGroups,
    required this.isRefreshing,
    required this.onEngineChanged,
    required this.onCycleChanged,
    required this.onGroupChanged,
    required this.onSensorChanged,
  });

  final FilterOptions filterOptions;
  final int? selectedEngineId;
  final int? selectedCycleId;
  final String selectedGroup;
  final String? selectedSensor;
  final SensorGroupsResponse? sensorGroups;
  final bool isRefreshing;
  final ValueChanged<int?> onEngineChanged;
  final ValueChanged<int?> onCycleChanged;
  final ValueChanged<String?> onGroupChanged;
  final ValueChanged<String?> onSensorChanged;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sensor Trends', style: AppText.sectionTitle),
                    const SizedBox(height: 10),
                    Text(
                      'Real-time sensor data visualization with filtering controls',
                      style: AppText.subtitle,
                    ),
                  ],
                ),
              ),
              if (isRefreshing)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.3),
                ),
            ],
          ),
          const SizedBox(height: 24),
          _SensorFilterBar(
            filterOptions: filterOptions,
            selectedEngineId: selectedEngineId,
            selectedCycleId: selectedCycleId,
            selectedGroup: selectedGroup,
            selectedSensor: selectedSensor,
            sensorGroups: sensorGroups,
            onEngineChanged: onEngineChanged,
            onCycleChanged: onCycleChanged,
            onGroupChanged: onGroupChanged,
            onSensorChanged: onSensorChanged,
          ),
          const SizedBox(height: 22),
          RepaintBoundary(
            child: _SensorLineChart(
              sensorGroups: sensorGroups,
              selectedGroup: selectedGroup,
              selectedSensor: selectedSensor,
            ),
          ),
        ],
      ),
    );
  }
}

class _SensorFilterBar extends StatelessWidget {
  const _SensorFilterBar({
    required this.filterOptions,
    required this.selectedEngineId,
    required this.selectedCycleId,
    required this.selectedGroup,
    required this.selectedSensor,
    required this.sensorGroups,
    required this.onEngineChanged,
    required this.onCycleChanged,
    required this.onGroupChanged,
    required this.onSensorChanged,
  });

  final FilterOptions filterOptions;
  final int? selectedEngineId;
  final int? selectedCycleId;
  final String selectedGroup;
  final String? selectedSensor;
  final SensorGroupsResponse? sensorGroups;
  final ValueChanged<int?> onEngineChanged;
  final ValueChanged<int?> onCycleChanged;
  final ValueChanged<String?> onGroupChanged;
  final ValueChanged<String?> onSensorChanged;

  @override
  Widget build(BuildContext context) {
    final cycles = selectedEngineId == null
        ? filterOptions.cycles
        : filterOptions.cyclesForEngine(selectedEngineId!);
    final engineValue = filterOptions.engines.contains(selectedEngineId)
        ? selectedEngineId
        : null;
    final cycleValue = cycles.contains(selectedCycleId) ? selectedCycleId : null;
    final sensorFeatures = (sensorGroups?.series[selectedGroup]?.keys.toList() ?? <String>[])..sort();
    final sensorValue = selectedSensor != null && sensorFeatures.contains(selectedSensor)
        ? selectedSensor
        : '__all__';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.softCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _DropdownField<int>(
              label: 'Engine',
              value: engineValue,
              hint: 'Select engine',
              items: filterOptions.engines
                  .map((engine) => DropdownMenuItem<int>(
                        value: engine,
                        child: Text(formatEngineId(engine)),
                      ))
                  .toList(),
              onChanged: onEngineChanged,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _DropdownField<int>(
              label: 'Cycle ID',
              value: cycleValue,
              hint: 'Select cycle',
              items: cycles
                  .map((cycle) => DropdownMenuItem<int>(
                        value: cycle,
                        child: Text(cycle.toString()),
                      ))
                  .toList(),
              onChanged: onCycleChanged,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _DropdownField<String>(
              label: 'Sensor Group',
              value: selectedGroup,
              hint: 'Select group',
              items: sensorGroupLabels.entries
                  .map((entry) => DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(entry.value),
                      ))
                  .toList(),
              onChanged: onGroupChanged,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _DropdownField<String>(
              label: 'Sensor',
              value: sensorValue,
              hint: 'All sensors',
              items: [
                const DropdownMenuItem<String>(
                  value: '__all__',
                  child: Text('All sensors'),
                ),
                ...sensorFeatures.map(
                  (feature) => DropdownMenuItem<String>(
                    value: feature,
                    child: Text(feature),
                  ),
                ),
              ],
              onChanged: onSensorChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.hint,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.filterLabel),
        const SizedBox(height: 8),
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppPalette.cardBackground,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppPalette.borderSoft),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              borderRadius: BorderRadius.circular(12),
              dropdownColor: AppPalette.cardBackground,
              hint: Text(hint, style: AppText.input.copyWith(color: AppPalette.textMuted)),
              style: AppText.input.copyWith(color: AppPalette.textPrimary),
              items: items,
              onChanged: items.isEmpty ? null : onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _SensorLineChart extends StatelessWidget {
  const _SensorLineChart({
    required this.sensorGroups,
    required this.selectedGroup,
    required this.selectedSensor,
  });

  final SensorGroupsResponse? sensorGroups;
  final String selectedGroup;
  final String? selectedSensor;

  @override
  Widget build(BuildContext context) {
    final data = sensorGroups;
    final groupValues = data?.series[selectedGroup] ?? const <String, List<double?>>{};
    final groupMap = selectedSensor != null && groupValues.containsKey(selectedSensor)
        ? <String, List<double?>>{selectedSensor!: groupValues[selectedSensor]!}
        : groupValues;
    final timesteps = data?.timesteps ?? const <int>[];

    if (data == null || timesteps.isEmpty || groupMap.isEmpty) {
      return const _EmptyState(
        icon: Icons.show_chart_rounded,
        title: 'No sensor trend selected',
        message: 'Choose an engine and cycle to display sensor trends.',
      );
    }

    final series = _buildChartSeries(timesteps: timesteps, valuesByFeature: groupMap);

    if (series.isEmpty) {
      return const _EmptyState(
        icon: Icons.query_stats_rounded,
        title: 'No chart data available',
        message: 'The selected engine and cycle do not contain values for this sensor group.',
      );
    }

    final chartMaxX = series.fold<double>(0, (maxValue, item) {
      if (item.normalizedSpots.isEmpty) return maxValue;
      return math.max(maxValue, item.normalizedSpots.last.x);
    });

    return Container(
      height: 350,
      padding: const EdgeInsets.fromLTRB(12, 14, 20, 8),
      decoration: BoxDecoration(
        color: AppPalette.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.borderSoft),
      ),
      child: Column(
        children: [
          Expanded(
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: chartMaxX <= 0 ? 100 : chartMaxX,
                minY: 0,
                maxY: 100,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppPalette.chartGrid,
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                  getDrawingVerticalLine: (_) => FlLine(
                    color: AppPalette.chartGrid,
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 38,
                      interval: 25,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: AppText.axis,
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: chartMaxX <= 0 ? 25 : chartMaxX / 4,
                      getTitlesWidget: (value, meta) {
                        final maxX = chartMaxX <= 0 ? 100.0 : chartMaxX;
                        final percent = ((value / maxX) * 100).round().clamp(0, 100);

                        if (percent != 0 && percent != 25 && percent != 50 && percent != 75 && percent != 100) {
                          return const SizedBox.shrink();
                        }

                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('$percent%', style: AppText.axis),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: const Border(
                    left: BorderSide(color: AppPalette.axisBorder),
                    bottom: BorderSide(color: AppPalette.axisBorder),
                  ),
                ),
                lineBarsData: [
                  for (final item in series)
                    LineChartBarData(
                      spots: item.normalizedSpots,
                      isCurved: true,
                      preventCurveOverShooting: true,
                      color: item.color,
                      barWidth: 2.4,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                ],
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItems: (spots) => spots.map((spot) {
                      if (spot.barIndex < 0 || spot.barIndex >= series.length) {
                        return null;
                      }

                      final item = series[spot.barIndex];
                      final rawValue = item.rawValueAt(spot.x);
                      final progress = chartMaxX <= 0 ? 0 : ((spot.x / chartMaxX) * 100).clamp(0, 100).round();

                      return LineTooltipItem(
                        '${item.feature}\nProgress $progress%\nValue ${formatNumber(rawValue)}',
                        AppText.tooltip,
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final item in series)
                _LegendItem(color: item.color, label: item.feature),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Trend lines are normalized per feature for comparison. Hover the line to see the raw sensor value.',
            style: AppText.subtitle,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  List<_SensorChartSeries> _buildChartSeries({
    required List<int> timesteps,
    required Map<String, List<double?>> valuesByFeature,
  }) {
    final result = <_SensorChartSeries>[];
    final colors = [
      AppPalette.red,
      AppPalette.amber,
      AppPalette.blue,
      AppPalette.green,
      AppPalette.purple,
      AppPalette.teal,
      const Color(0xFFEA580C),
    ];

    var colorIndex = 0;
    for (final entry in valuesByFeature.entries) {
      final rawSpots = <FlSpot>[];
      final maxLength = math.min(timesteps.length, entry.value.length);

      for (int index = 0; index < maxLength; index++) {
        final value = entry.value[index];
        if (value == null || value.isNaN || value.isInfinite) continue;
        rawSpots.add(FlSpot(timesteps[index].toDouble(), value));
      }

      if (rawSpots.length < 2) continue;

      final rawValues = rawSpots.map((spot) => spot.y).toList();
      final minValue = rawValues.reduce(math.min);
      final maxValue = rawValues.reduce(math.max);
      final range = (maxValue - minValue).abs() < 0.000001 ? 1.0 : maxValue - minValue;

      final normalized = rawSpots
          .map((spot) => FlSpot(spot.x, ((spot.y - minValue) / range) * 100.0))
          .toList();

      result.add(
        _SensorChartSeries(
          feature: entry.key,
          color: colors[colorIndex % colors.length],
          normalizedSpots: _downsampleSpots(normalized, maxPoints: 280),
          rawSpots: rawSpots,
        ),
      );
      colorIndex++;
    }

    return result;
  }

  List<FlSpot> _downsampleSpots(List<FlSpot> spots, {required int maxPoints}) {
    if (spots.length <= maxPoints) return spots;
    final result = <FlSpot>[];
    final step = (spots.length - 1) / (maxPoints - 1);
    for (int i = 0; i < maxPoints; i++) {
      final index = (i * step).round().clamp(0, spots.length - 1);
      result.add(spots[index]);
    }
    return result;
  }
}

class _SensorChartSeries {
  const _SensorChartSeries({
    required this.feature,
    required this.color,
    required this.normalizedSpots,
    required this.rawSpots,
  });

  final String feature;
  final Color color;
  final List<FlSpot> normalizedSpots;
  final List<FlSpot> rawSpots;

  double rawValueAt(double x) {
    if (rawSpots.isEmpty) return 0;
    FlSpot closest = rawSpots.first;
    double bestDistance = (closest.x - x).abs();

    for (final spot in rawSpots) {
      final distance = (spot.x - x).abs();
      if (distance < bestDistance) {
        closest = spot;
        bestDistance = distance;
      }
    }

    return closest.y;
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(label, style: AppText.legend),
      ],
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppPalette.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      decoration: BoxDecoration(
        color: AppPalette.softCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.borderSoft),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: AppPalette.textSoft),
          const SizedBox(height: 12),
          Text(title, style: AppText.sectionTitle),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: AppText.subtitle),
        ],
      ),
    );
  }
}

class _CenteredCard extends StatelessWidget {
  const _CenteredCard({
    required this.icon,
    required this.title,
    required this.message,
    this.showProgress = false,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool showProgress;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppPalette.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppPalette.blue),
            const SizedBox(height: 16),
            Text(title, style: AppText.sectionTitle),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center, style: AppText.subtitle),
            if (showProgress) ...[
              const SizedBox(height: 18),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(
                  backgroundColor: AppPalette.primaryBlack,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnalyticsApi {
  _AnalyticsApi()
      : _dio = Dio(
          BaseOptions(
            baseUrl: 'http://127.0.0.1:8000',
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 20),
          ),
        );

  final Dio _dio;

  Future<List<FleetEngine>> fetchEngines() async {
    final response = await _dio.get<dynamic>('/engines');
    final data = response.data;

    if (data is List) {
      return data
          .whereType<Map>()
          .map((item) => FleetEngine.fromJson(_mapDynamic(item)))
          .toList();
    }

    return [];
  }

  Future<FleetSummary> fetchFleetSummary() async {
    final response = await _dio.get<dynamic>('/dashboard-summary');
    final data = response.data;

    if (data is Map) {
      return FleetSummary.fromJson(_mapDynamic(data));
    }

    return FleetSummary.empty();
  }

  Future<MonthPredictionSummary> fetchMonthPredictionSummary() async {
    final response = await _dio.get<dynamic>('/analytics/predictions-this-month');
    final data = response.data;

    if (data is Map) {
      return MonthPredictionSummary.fromJson(_mapDynamic(data));
    }

    return MonthPredictionSummary.empty();
  }

  Future<FilterOptions> fetchFilterOptions() async {
    final response = await _dio.get<dynamic>('/analytics/filter-options');
    final data = response.data;

    if (data is Map) {
      return FilterOptions.fromJson(_mapDynamic(data));
    }

    return FilterOptions.empty();
  }

  Future<SensorGroupsResponse> fetchSensorGroups({
    required int engineId,
    required int cycleId,
  }) async {
    final response = await _dio.get<dynamic>(
      '/analytics/sensor-groups',
      queryParameters: {
        'engine_id': engineId,
        'cycle_id': cycleId,
      },
    );

    final data = response.data;

    if (data is Map) {
      return SensorGroupsResponse.fromJson(_mapDynamic(data));
    }

    return SensorGroupsResponse.empty();
  }

  Map<String, dynamic> _mapDynamic(Map map) {
    return map.map((key, value) => MapEntry(key.toString(), value));
  }
}

class FleetEngine {
  const FleetEngine({
    required this.engineId,
    required this.status,
    required this.rul,
    required this.cycleId,
    required this.timestamp,
  });

  final int engineId;
  final String status;
  final double rul;
  final int? cycleId;
  final String? timestamp;

  String get displayEngineId => formatEngineId(engineId);

  factory FleetEngine.fromJson(Map<String, dynamic> json) {
    return FleetEngine(
      engineId: _intFrom(json['engine_id']) ?? 0,
      status: (json['status'] ?? 'unknown').toString(),
      rul: _doubleFrom(json['rul']) ?? 0.0,
      cycleId: _intFrom(json['cycle_id']),
      timestamp: json['timestamp']?.toString(),
    );
  }
}

class FleetSummary {
  const FleetSummary({
    required this.ok,
    required this.watch,
    required this.critical,
    required this.activeAlerts,
  });

  final int ok;
  final int watch;
  final int critical;
  final int activeAlerts;

  factory FleetSummary.empty() {
    return const FleetSummary(ok: 0, watch: 0, critical: 0, activeAlerts: 0);
  }

  factory FleetSummary.fromJson(Map<String, dynamic> json) {
    final fleetHealth = json['fleet_health'];
    final fleetMap = fleetHealth is Map
        ? fleetHealth.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};

    return FleetSummary(
      ok: _intFrom(fleetMap['ok']) ?? 0,
      watch: _intFrom(fleetMap['watch']) ?? 0,
      critical: _intFrom(fleetMap['critical']) ?? 0,
      activeAlerts: _intFrom(json['active_alerts']) ?? 0,
    );
  }
}

class MonthPredictionSummary {
  const MonthPredictionSummary({
    required this.predictionsThisMonth,
    required this.enginesThisMonth,
  });

  final int predictionsThisMonth;
  final int enginesThisMonth;

  factory MonthPredictionSummary.empty() {
    return const MonthPredictionSummary(predictionsThisMonth: 0, enginesThisMonth: 0);
  }

  factory MonthPredictionSummary.fromJson(Map<String, dynamic> json) {
    return MonthPredictionSummary(
      predictionsThisMonth: _intFrom(json['predictions_this_month']) ?? 0,
      enginesThisMonth: _intFrom(json['engines_this_month']) ?? 0,
    );
  }
}

class FilterOptions {
  const FilterOptions({
    required this.engines,
    required this.cycles,
    required this.cyclesByEngine,
  });

  final List<int> engines;
  final List<int> cycles;
  final Map<int, List<int>> cyclesByEngine;

  factory FilterOptions.empty() => const FilterOptions(
        engines: [],
        cycles: [],
        cyclesByEngine: {},
      );

  List<int> cyclesForEngine(int engineId) {
    final engineCycles = cyclesByEngine[engineId] ?? const <int>[];
    if (engineCycles.isNotEmpty) return engineCycles;
    return cycles;
  }

  factory FilterOptions.fromJson(Map<String, dynamic> json) {
    final rawCyclesByEngine = json['cycles_by_engine'];
    final parsedCyclesByEngine = <int, List<int>>{};
    final allCycles = <int>{};

    if (rawCyclesByEngine is Map) {
      rawCyclesByEngine.forEach((key, value) {
        final engineId = _intFrom(key);
        if (engineId == null) return;

        final cycleList = _intListFrom(value)..sort();
        if (cycleList.isEmpty) return;

        parsedCyclesByEngine[engineId] = cycleList;
        allCycles.addAll(cycleList);
      });
    }

    final legacyCycles = _intListFrom(json['cycles']);
    allCycles.addAll(legacyCycles);

    final sortedCycles = allCycles.toList()..sort();

    return FilterOptions(
      engines: _intListFrom(json['engines']),
      cycles: sortedCycles,
      cyclesByEngine: parsedCyclesByEngine,
    );
  }
}

class SensorGroupsResponse {
  const SensorGroupsResponse({
    required this.engineId,
    required this.cycleId,
    required this.rowCount,
    required this.timesteps,
    required this.series,
  });

  final int engineId;
  final int cycleId;
  final int rowCount;
  final List<int> timesteps;
  final Map<String, Map<String, List<double?>>> series;

  factory SensorGroupsResponse.empty() {
    return const SensorGroupsResponse(
      engineId: 0,
      cycleId: 0,
      rowCount: 0,
      timesteps: [],
      series: {},
    );
  }

  factory SensorGroupsResponse.fromJson(Map<String, dynamic> json) {
    final rawSeries = json['series'];
    final parsedSeries = <String, Map<String, List<double?>>>{};

    if (rawSeries is Map) {
      for (final groupEntry in rawSeries.entries) {
        final groupName = groupEntry.key.toString();
        final groupValue = groupEntry.value;
        final features = <String, List<double?>>{};

        if (groupValue is Map) {
          for (final featureEntry in groupValue.entries) {
            features[featureEntry.key.toString()] = _nullableDoubleListFrom(featureEntry.value);
          }
        }

        parsedSeries[groupName] = features;
      }
    }

    return SensorGroupsResponse(
      engineId: _intFrom(json['engine_id']) ?? 0,
      cycleId: _intFrom(json['cycle_id']) ?? 0,
      rowCount: _intFrom(json['row_count']) ?? 0,
      timesteps: _intListFrom(json['timesteps']),
      series: parsedSeries,
    );
  }
}

int? _intFrom(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? _doubleFrom(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

List<int> _intListFrom(dynamic value) {
  if (value is! List) return [];
  return value.map(_intFrom).whereType<int>().toList();
}

List<double?> _nullableDoubleListFrom(dynamic value) {
  if (value is! List) return [];
  return value.map(_doubleFrom).toList();
}

enum EngineStatus { ok, watch, critical, unknown }

EngineStatus normalizeStatus(String value) {
  final raw = value.trim().toLowerCase();
  if (raw == 'ok' || raw == 'normal' || raw == 'low') return EngineStatus.ok;
  if (raw == 'watch' || raw == 'warning' || raw == 'medium') return EngineStatus.watch;
  if (raw == 'critical' || raw == 'high') return EngineStatus.critical;
  return EngineStatus.unknown;
}

Color statusColor(EngineStatus status) {
  switch (status) {
    case EngineStatus.ok:
      return AppPalette.green;
    case EngineStatus.watch:
      return AppPalette.amber;
    case EngineStatus.critical:
      return AppPalette.red;
    case EngineStatus.unknown:
      return AppPalette.textSoft;
  }
}

String statusDisplayName(EngineStatus status) {
  switch (status) {
    case EngineStatus.ok:
      return 'OK';
    case EngineStatus.watch:
      return 'Watch';
    case EngineStatus.critical:
      return 'Critical';
    case EngineStatus.unknown:
      return 'Unknown';
  }
}

String formatEngineId(int engineId) {
  return 'ENG-${engineId.toString().padLeft(4, '0')}';
}

String formatNumber(double value) {
  if (value.abs() >= 100) return value.toStringAsFixed(0);
  if (value.abs() >= 10) return value.toStringAsFixed(1);
  return value.toStringAsFixed(3);
}

const sensorGroupLabels = <String, String>{
  'temperature': 'Temperature',
  'pressure': 'Pressure',
  'speed': 'Speed',
  'fuel': 'Fuel',
  'operating_context': 'Operating Context',
};

class AppPalette {
  static const Color pageBackground = Color(0xFFF6F7F9);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color softCard = Color(0xFFF8F9FB);
  static const Color inputFill = Color(0xFFF3F4F6);
  static const Color border = Color(0xFFDDE2E8);
  static const Color borderSoft = Color(0xFFE5E7EB);
  static const Color primaryBlack = Color(0xFF030014);
  static const Color textPrimary = Color(0xFF020617);
  static const Color textMuted = Color(0xFF667085);
  static const Color textSoft = Color(0xFF98A2B3);
  static const Color axisText = Color(0xFF475467);
  static const Color axisBorder = Color(0xFF9CA3AF);
  static const Color chartGrid = Color(0xFFD7DCE4);
  static const Color track = Color(0xFFE5E7EB);
  static const Color blue = Color(0xFF2563EB);
  static const Color green = Color(0xFF22C55E);
  static const Color amber = Color(0xFFF2B705);
  static const Color red = Color(0xFFEF4444);
  static const Color purple = Color(0xFF7C3AED);
  static const Color teal = Color(0xFF14B8A6);
}

class AppText {
  static TextStyle get _base => GoogleFonts.inter();

  static TextStyle get pageTitle => _base.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: AppPalette.textPrimary,
        height: 1.12,
      );

  static TextStyle get sectionTitle => _base.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: AppPalette.textPrimary,
      );

  static TextStyle get subtitle => _base.copyWith(
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w500,
        color: AppPalette.textMuted,
      );

  static TextStyle get metricTitle => _base.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppPalette.textMuted,
      );

  static TextStyle get metricValue => _base.copyWith(
        fontSize: 27,
        fontWeight: FontWeight.w800,
        color: AppPalette.textPrimary,
        height: 1.05,
      );

  static TextStyle get tableHeader => _base.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppPalette.textPrimary,
      );

  static TextStyle get tableBody => _base.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppPalette.textPrimary,
      );

  static TextStyle get badge => _base.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w800,
      );

  static TextStyle get filterLabel => _base.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppPalette.textPrimary,
      );

  static TextStyle get input => _base.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
      );

  static TextStyle get axis => _base.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppPalette.axisText,
      );

  static TextStyle get legend => _base.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppPalette.axisText,
      );

  static TextStyle get tooltip => _base.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        height: 1.3,
      );
}

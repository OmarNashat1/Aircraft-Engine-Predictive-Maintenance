import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:predection_desktop_app/shared/layouts/main_layout.dart';

const String _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _apiBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 90),
      sendTimeout: const Duration(seconds: 60),
    ),
  );

  final TextEditingController _searchController = TextEditingController();

  List<AlertItem> _alerts = <AlertItem>[];
  Map<int, PredictionDetails> _predictionDetailsById = <int, PredictionDetails>{};

  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isResolving = false;
  String? _errorMessage;
  AlertItem? _selectedAlert;
  String _statusFilter = 'open';
  String _levelFilter = 'all';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadAlerts({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _isRefreshing = true;
        _errorMessage = null;
      });
    }

    try {
      final response = await _dio.get<dynamic>('/alerts');
      final data = response.data;

      if (data is Map && data.containsKey('error')) {
        throw Exception(data['error']);
      }

      if (data is! List) {
        throw Exception('Unexpected alerts response format.');
      }

      final alerts = data
          .whereType<Map>()
          .map((item) => AlertItem.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ))
          .toList();

      alerts.sort((a, b) {
        if (a.isResolved != b.isResolved) {
          return a.isResolved ? 1 : -1;
        }
        return b.createdSortValue.compareTo(a.createdSortValue);
      });

      final details = await _loadPredictionDetails(alerts);

      if (!mounted) return;
      setState(() {
        _alerts = alerts;
        _predictionDetailsById = details;
        _isLoading = false;
        _isRefreshing = false;
        if (_selectedAlert != null) {
          AlertItem? updatedSelected;
          for (final item in alerts) {
            if (item.alertId == _selectedAlert!.alertId) {
              updatedSelected = item;
              break;
            }
          }
          _selectedAlert = updatedSelected;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<Map<int, PredictionDetails>> _loadPredictionDetails(List<AlertItem> alerts) async {
    final ids = alerts
        .map((alert) => alert.predictionId)
        .whereType<int>()
        .toSet()
        .toList();

    final details = <int, PredictionDetails>{};

    await Future.wait(ids.map((id) async {
      try {
        final response = await _dio.get<dynamic>('/results/$id');
        final data = response.data;

        if (data is Map && !data.containsKey('error')) {
          details[id] = PredictionDetails.fromJson(
            data.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      } catch (_) {
        // The alerts page can still render using /alerts even if a linked
        // prediction could not be loaded.
      }
    }));

    return details;
  }

  List<AlertItem> get _visibleAlerts {
    final search = _searchController.text.trim().toLowerCase();

    return _alerts.where((alert) {
      final details = alert.predictionId == null
          ? null
          : _predictionDetailsById[alert.predictionId!];

      final statusMatches = switch (_statusFilter) {
        'open' => !alert.isResolved,
        'resolved' => alert.isResolved,
        _ => true,
      };

      final levelMatches = _levelFilter == 'all' || alert.normalizedLevel == _levelFilter;

      final searchMatches = search.isEmpty ||
          alert.displayId.toLowerCase().contains(search) ||
          alert.message.toLowerCase().contains(search) ||
          alert.normalizedLevel.toLowerCase().contains(search) ||
          (alert.predictionId?.toString().contains(search) ?? false) ||
          (details?.engineLabel.toLowerCase().contains(search) ?? false) ||
          (details?.cycleId.toString().contains(search) ?? false);

      return statusMatches && levelMatches && searchMatches;
    }).toList();
  }

  int get _openCount => _alerts.where((alert) => !alert.isResolved).length;
  int get _criticalOpenCount => _alerts
      .where((alert) => !alert.isResolved && alert.normalizedLevel == 'critical')
      .length;
  int get _watchOpenCount => _alerts
      .where((alert) => !alert.isResolved && alert.normalizedLevel == 'watch')
      .length;
  int get _resolvedCount => _alerts.where((alert) => alert.isResolved).length;

  Future<void> _acknowledgeAlert(AlertItem alert) async {
    if (_isResolving || alert.isResolved) return;

    setState(() => _isResolving = true);

    try {
      Response<dynamic>? response;

      try {
        response = await _dio.post<dynamic>('/alerts/${alert.alertId}/resolve');
      } on DioException {
        response = await _dio.post<dynamic>('/alerts/${alert.alertId}/acknowledge');
      }

      final data = response.data;
      if (data is Map && data.containsKey('error')) {
        throw Exception(data['error']);
      }

      if (!mounted) return;
      setState(() {
        _alerts = _alerts
            .map((item) => item.alertId == alert.alertId
                ? item.copyWith(isResolved: true)
                : item)
            .toList();
        if (_selectedAlert?.alertId == alert.alertId) {
          _selectedAlert = _selectedAlert!.copyWith(isResolved: true);
        }
        _isResolving = false;
      });

      _showResolvedPopup(alert);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isResolving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to acknowledge alert. Make sure the backend resolve endpoint was added. ${error.toString().replaceFirst('Exception: ', '')}',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppPalette.critical,
        ),
      );
    }
  }


  void _showResolvedPopup(AlertItem alert) {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => Positioned(
        right: 28,
        bottom: 28,
        child: _ResolvedToast(
          alertId: alert.displayId,
          onClose: () => entry.remove(),
        ),
      ),
    );

    overlay.insert(entry);
    Future<void>.delayed(const Duration(milliseconds: 2600), () {
      if (entry.mounted) {
        entry.remove();
      }
    });
  }

  void _openPrediction(AlertItem alert) {
    final predictionId = alert.predictionId;
    if (predictionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This alert is not linked to a prediction.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacementNamed('/results/$predictionId');
  }

  void _openDetails(AlertItem alert) {
    setState(() => _selectedAlert = alert);
  }

  void _closeDetails() {
    setState(() => _selectedAlert = null);
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      currentRoute: '/alerts',
      title: 'Predictive Maintenance Dashboard',
      child: Stack(
        children: [
          _buildContent(),
          _AlertDetailsOverlay(
            alert: _selectedAlert,
            details: _selectedAlert?.predictionId == null
                ? null
                : _predictionDetailsById[_selectedAlert!.predictionId!],
            isResolving: _isResolving,
            onClose: _closeDetails,
            onAcknowledge: _selectedAlert == null
                ? null
                : () => _acknowledgeAlert(_selectedAlert!),
            onOpenPrediction: _selectedAlert == null
                ? null
                : () => _openPrediction(_selectedAlert!),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _isLoading
          ? const _CenteredState(
              key: ValueKey('loading'),
              icon: Icons.notifications_active_outlined,
              title: 'Loading alerts',
              subtitle: 'Reading active alerts from the backend...',
              showProgress: true,
            )
          : _errorMessage != null
              ? _CenteredState(
                  key: const ValueKey('error'),
                  icon: Icons.error_outline_rounded,
                  title: 'Unable to load alerts',
                  subtitle: _errorMessage!,
                  actionLabel: 'Retry',
                  onAction: _loadAlerts,
                )
              : _buildDashboard(),
    );
  }

  Widget _buildDashboard() {
    final visibleAlerts = _visibleAlerts;

    return RefreshIndicator(
      onRefresh: () => _loadAlerts(silent: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 34),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Alerts & Notifications',
                        style: AppText.pageTitle,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Triage active prediction alerts and acknowledge resolved issues.',
                        style: AppText.body.copyWith(color: AppPalette.textMuted),
                      ),
                    ],
                  ),
                ),
                _IconButtonGhost(
                  icon: _isRefreshing ? Icons.hourglass_top_rounded : Icons.refresh_rounded,
                  tooltip: 'Refresh alerts',
                  onPressed: _isRefreshing ? null : () => _loadAlerts(silent: true),
                ),
              ],
            ),
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 900;
                final cards = [
                  _MetricCard(
                    label: 'Open Alerts',
                    value: _openCount.toString(),
                    caption: 'Unresolved alerts requiring review',
                    icon: Icons.notifications_none_rounded,
                    color: AppPalette.navy,
                  ),
                  _MetricCard(
                    label: 'Critical',
                    value: _criticalOpenCount.toString(),
                    caption: 'Critical unresolved alerts',
                    icon: Icons.warning_amber_rounded,
                    color: AppPalette.critical,
                  ),
                  _MetricCard(
                    label: 'Watch',
                    value: _watchOpenCount.toString(),
                    caption: 'Watch-level unresolved alerts',
                    icon: Icons.info_outline_rounded,
                    color: AppPalette.watch,
                  ),
                  _MetricCard(
                    label: 'Resolved',
                    value: _resolvedCount.toString(),
                    caption: 'Acknowledged alerts',
                    icon: Icons.check_circle_outline_rounded,
                    color: AppPalette.ok,
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

                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < cards.length; index++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: index == cards.length - 1 ? 0 : 12,
                            ),
                            child: cards[index],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            _FilterCard(
              searchController: _searchController,
              statusFilter: _statusFilter,
              levelFilter: _levelFilter,
              onStatusChanged: (value) => setState(() => _statusFilter = value),
              onLevelChanged: (value) => setState(() => _levelFilter = value),
              onReset: () {
                _searchController.clear();
                setState(() {
                  _statusFilter = 'open';
                  _levelFilter = 'all';
                });
              },
            ),
            const SizedBox(height: 18),
            _AlertsQueueCard(
              alerts: visibleAlerts,
              detailsByPredictionId: _predictionDetailsById,
              onViewDetails: _openDetails,
              onViewPrediction: _openPrediction,
              onAcknowledge: _acknowledgeAlert,
              isResolving: _isResolving,
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertsQueueCard extends StatelessWidget {
  const _AlertsQueueCard({
    required this.alerts,
    required this.detailsByPredictionId,
    required this.onViewDetails,
    required this.onViewPrediction,
    required this.onAcknowledge,
    required this.isResolving,
  });

  final List<AlertItem> alerts;
  final Map<int, PredictionDetails> detailsByPredictionId;
  final ValueChanged<AlertItem> onViewDetails;
  final ValueChanged<AlertItem> onViewPrediction;
  final ValueChanged<AlertItem> onAcknowledge;
  final bool isResolving;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Row(
              children: [
                Expanded(
                  child: Text('Open Alerts Queue', style: AppText.sectionTitle),
                ),
                Text(
                  '${alerts.length} shown',
                  style: AppText.caption.copyWith(color: AppPalette.textMuted),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppPalette.border),
          if (alerts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 52),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.notifications_off_outlined, color: AppPalette.textMuted, size: 34),
                    SizedBox(height: 10),
                    Text('No alerts match the current filters.'),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: alerts.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppPalette.border),
              itemBuilder: (context, index) {
                final alert = alerts[index];
                final details = alert.predictionId == null
                    ? null
                    : detailsByPredictionId[alert.predictionId!];
                return _AlertQueueRow(
                  alert: alert,
                  details: details,
                  onViewDetails: () => onViewDetails(alert),
                  onViewPrediction: () => onViewPrediction(alert),
                  onAcknowledge: () => onAcknowledge(alert),
                  isResolving: isResolving,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _AlertQueueRow extends StatelessWidget {
  const _AlertQueueRow({
    required this.alert,
    required this.details,
    required this.onViewDetails,
    required this.onViewPrediction,
    required this.onAcknowledge,
    required this.isResolving,
  });

  final AlertItem alert;
  final PredictionDetails? details;
  final VoidCallback onViewDetails;
  final VoidCallback onViewPrediction;
  final VoidCallback onAcknowledge;
  final bool isResolving;

  @override
  Widget build(BuildContext context) {
    final levelStyle = _AlertLevelStyle.fromLevel(alert.normalizedLevel);
    final resolved = alert.isResolved;
    final rowDetails = details;

    return InkWell(
      onTap: onViewDetails,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 14, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              resolved ? Icons.check_circle_outline_rounded : levelStyle.icon,
              size: 20,
              color: resolved ? AppPalette.ok : levelStyle.color,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(alert.displayId, style: AppText.rowTitle),
                      const SizedBox(width: 8),
                      _Badge(label: levelStyle.label, color: levelStyle.color),
                      if (resolved) ...[
                        const SizedBox(width: 6),
                        const _Badge(label: 'resolved', color: AppPalette.ok),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    details?.engineSummary ?? alert.linkedPredictionText,
                    style: AppText.caption.copyWith(
                      color: AppPalette.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    alert.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: AppText.caption.copyWith(color: AppPalette.textMuted),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      _MetaText(
                        icon: Icons.schedule_rounded,
                        text: 'Created: ${alert.createdAtText}',
                      ),
                      if (alert.predictionId != null)
                        _MetaText(
                          icon: Icons.analytics_outlined,
                          text: 'Prediction #${alert.predictionId}',
                        ),
                      if (rowDetails != null)
                        _MetaText(
                          icon: Icons.data_usage_rounded,
                          text: 'RUL: ${rowDetails.rulText}',
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                _SmallOutlineButton(
                  icon: Icons.visibility_outlined,
                  label: 'View Details',
                  onPressed: onViewDetails,
                ),
                _SmallOutlineButton(
                  icon: Icons.open_in_new_rounded,
                  label: 'View Prediction',
                  onPressed: alert.predictionId == null ? null : onViewPrediction,
                ),
                if (!resolved)
                  _SmallPrimaryButton(
                    icon: Icons.check_circle_outline_rounded,
                    label: isResolving ? 'Saving...' : 'Acknowledge',
                    onPressed: isResolving ? null : onAcknowledge,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertDetailsOverlay extends StatelessWidget {
  const _AlertDetailsOverlay({
    required this.alert,
    required this.details,
    required this.isResolving,
    required this.onClose,
    required this.onAcknowledge,
    required this.onOpenPrediction,
  });

  final AlertItem? alert;
  final PredictionDetails? details;
  final bool isResolving;
  final VoidCallback onClose;
  final VoidCallback? onAcknowledge;
  final VoidCallback? onOpenPrediction;

  @override
  Widget build(BuildContext context) {
    final active = alert != null;

    return IgnorePointer(
      ignoring: !active,
      child: Stack(
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            opacity: active ? 1 : 0,
            child: GestureDetector(
              onTap: onClose,
              child: Container(color: Colors.black.withOpacity(0.48)),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            top: 0,
            bottom: 0,
            right: active ? 0 : -390,
            width: 390,
            child: Material(
              color: Colors.white,
              elevation: 18,
              child: active
                  ? _AlertDetailsPanel(
                      alert: alert!,
                      details: details,
                      isResolving: isResolving,
                      onClose: onClose,
                      onAcknowledge: onAcknowledge,
                      onOpenPrediction: onOpenPrediction,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertDetailsPanel extends StatelessWidget {
  const _AlertDetailsPanel({
    required this.alert,
    required this.details,
    required this.isResolving,
    required this.onClose,
    required this.onAcknowledge,
    required this.onOpenPrediction,
  });

  final AlertItem alert;
  final PredictionDetails? details;
  final bool isResolving;
  final VoidCallback onClose;
  final VoidCallback? onAcknowledge;
  final VoidCallback? onOpenPrediction;

  @override
  Widget build(BuildContext context) {
    final levelStyle = _AlertLevelStyle.fromLevel(alert.normalizedLevel);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Alert Details - ${alert.displayId}',
                    style: AppText.sectionTitle,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Badge(label: levelStyle.label, color: levelStyle.color),
                      if (alert.isResolved)
                        const _Badge(label: 'resolved', color: AppPalette.ok)
                      else
                        const _Badge(label: 'open', color: AppPalette.navy),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _InfoBlock(
                    title: 'Message',
                    value: alert.message,
                  ),
                  const SizedBox(height: 14),
                  _InfoBlock(
                    title: 'Linked Prediction',
                    value: details?.fullSummary ?? alert.linkedPredictionText,
                  ),
                  const SizedBox(height: 22),
                  Text('Timeline', style: AppText.sectionTitle),
                  const SizedBox(height: 12),
                  _TimelineItem(
                    color: levelStyle.color,
                    title: 'Alert created',
                    subtitle: alert.createdAtText,
                  ),
                  const SizedBox(height: 10),
                  _TimelineItem(
                    color: alert.isResolved ? AppPalette.ok : AppPalette.blue,
                    title: alert.isResolved ? 'Alert resolved' : 'Awaiting acknowledgement',
                    subtitle: alert.isResolved
                        ? 'Marked resolved in the alert queue'
                        : 'Use Acknowledge to mark this alert as resolved',
                  ),
                  const SizedBox(height: 24),
                  Text('Available Actions', style: AppText.sectionTitle),
                  const SizedBox(height: 12),
                  _FullWidthButton(
                    icon: Icons.open_in_new_rounded,
                    label: 'View Prediction',
                    primary: false,
                    onPressed: onOpenPrediction,
                  ),
                  const SizedBox(height: 10),
                  if (!alert.isResolved)
                    _FullWidthButton(
                      icon: Icons.check_circle_outline_rounded,
                      label: isResolving ? 'Acknowledging...' : 'Acknowledge and Mark Resolved',
                      primary: true,
                      onPressed: isResolving ? null : onAcknowledge,
                    )
                  else
                    const _ResolvedBox(),
                  const SizedBox(height: 10),
                  _FullWidthButton(
                    icon: Icons.close_rounded,
                    label: 'Close Panel',
                    primary: false,
                    onPressed: onClose,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'This page only uses alert fields available from the backend: alert id, linked prediction id, alert level, message, created time, and resolved state. Prediction details are loaded from the linked result when available.',
                    style: AppText.caption.copyWith(color: AppPalette.textMuted, height: 1.45),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterCard extends StatelessWidget {
  const _FilterCard({
    required this.searchController,
    required this.statusFilter,
    required this.levelFilter,
    required this.onStatusChanged,
    required this.onLevelChanged,
    required this.onReset,
  });

  final TextEditingController searchController;
  final String statusFilter;
  final String levelFilter;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onLevelChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Alert Filters', style: AppText.sectionTitle),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 840;
              final children = [
                Expanded(
                  flex: 2,
                  child: _SearchField(
                    controller: searchController,
                    hintText: 'Search alert, prediction, engine...',
                  ),
                ),
                const SizedBox(width: 14, height: 14),
                Expanded(
                  child: _DropdownField(
                    label: 'Queue',
                    value: statusFilter,
                    options: const {
                      'open': 'Open alerts',
                      'resolved': 'Resolved alerts',
                      'all': 'All alerts',
                    },
                    onChanged: onStatusChanged,
                  ),
                ),
                const SizedBox(width: 14, height: 14),
                Expanded(
                  child: _DropdownField(
                    label: 'Level',
                    value: levelFilter,
                    options: const {
                      'all': 'All levels',
                      'critical': 'Critical',
                      'watch': 'Watch',
                      'ok': 'OK',
                    },
                    onChanged: onLevelChanged,
                  ),
                ),
                const SizedBox(width: 14, height: 14),
                _SmallOutlineButton(
                  icon: Icons.restart_alt_rounded,
                  label: 'Reset',
                  onPressed: onReset,
                ),
              ];

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SearchField(
                      controller: searchController,
                      hintText: 'Search alert, prediction, engine...',
                    ),
                    const SizedBox(height: 12),
                    _DropdownField(
                      label: 'Queue',
                      value: statusFilter,
                      options: const {
                        'open': 'Open alerts',
                        'resolved': 'Resolved alerts',
                        'all': 'All alerts',
                      },
                      onChanged: onStatusChanged,
                    ),
                    const SizedBox(height: 12),
                    _DropdownField(
                      label: 'Level',
                      value: levelFilter,
                      options: const {
                        'all': 'All levels',
                        'critical': 'Critical',
                        'watch': 'Watch',
                        'ok': 'OK',
                      },
                      onChanged: onLevelChanged,
                    ),
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerLeft, child: children.last),
                  ],
                );
              }

              return Row(crossAxisAlignment: CrossAxisAlignment.end, children: children);
            },
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: SizedBox(
        height: 112,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: AppPalette.textMuted),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: AppText.metric.copyWith(color: color)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: AppText.caption.copyWith(color: AppPalette.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, this.padding = const EdgeInsets.all(18)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.hintText});

  final TextEditingController controller;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: AppText.body,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search_rounded, size: 19),
        filled: true,
        fillColor: AppPalette.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppPalette.blue, width: 1.2),
        ),
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = options.containsKey(value) ? value : options.keys.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            label,
            style: AppText.caption.copyWith(
              color: AppPalette.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppPalette.inputFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.transparent),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: safeValue,
              isExpanded: true,
              borderRadius: BorderRadius.circular(12),
              dropdownColor: AppPalette.card,
              menuMaxHeight: 260,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppPalette.textMuted,
              ),
              style: AppText.body.copyWith(color: AppPalette.text),
              selectedItemBuilder: (context) {
                return options.values
                    .map(
                      (labelText) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          labelText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body.copyWith(color: AppPalette.text),
                        ),
                      ),
                    )
                    .toList();
              },
              items: options.entries
                  .map(
                    (entry) => DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text(
                        entry.value,
                        style: AppText.body.copyWith(color: AppPalette.text),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (newValue) {
                if (newValue != null) onChanged(newValue);
              },
            ),
          ),
        ),
      ],
    );
  }
}
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Text(
        label,
        style: AppText.badge.copyWith(color: color),
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppPalette.textMuted),
        const SizedBox(width: 4),
        Text(text, style: AppText.tiny.copyWith(color: AppPalette.textMuted)),
      ],
    );
  }
}

class _SmallOutlineButton extends StatelessWidget {
  const _SmallOutlineButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppPalette.navy,
        disabledForegroundColor: AppPalette.textMuted,
        side: const BorderSide(color: AppPalette.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        textStyle: AppText.button,
      ),
    );
  }
}

class _SmallPrimaryButton extends StatelessWidget {
  const _SmallPrimaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppPalette.navy,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppPalette.navy.withOpacity(0.45),
        disabledForegroundColor: Colors.white70,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        textStyle: AppText.button,
      ),
    );
  }
}

class _FullWidthButton extends StatelessWidget {
  const _FullWidthButton({
    required this.icon,
    required this.label,
    required this.primary,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ButtonStyle style = primary
        ? ElevatedButton.styleFrom(
            backgroundColor: AppPalette.navy,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppPalette.navy.withOpacity(0.45),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            padding: const EdgeInsets.symmetric(vertical: 15),
            textStyle: AppText.button,
          )
        : OutlinedButton.styleFrom(
            foregroundColor: AppPalette.navy,
            disabledForegroundColor: AppPalette.textMuted,
            side: const BorderSide(color: AppPalette.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            padding: const EdgeInsets.symmetric(vertical: 15),
            textStyle: AppText.button,
          );

    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: 8),
        Text(label),
      ],
    );

    return SizedBox(
      width: double.infinity,
      child: primary
          ? ElevatedButton(onPressed: onPressed, style: style, child: child)
          : OutlinedButton(onPressed: onPressed, style: style, child: child),
    );
  }
}

class _IconButtonGhost extends StatelessWidget {
  const _IconButtonGhost({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: AppPalette.blue),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: AppPalette.border),
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.inputFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.caption.copyWith(color: AppPalette.textMuted)),
          const SizedBox(height: 8),
          Text(value, style: AppText.body.copyWith(height: 1.45)),
        ],
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 9,
          height: 9,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.caption.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(subtitle, style: AppText.tiny.copyWith(color: AppPalette.textMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResolvedBox extends StatelessWidget {
  const _ResolvedBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      decoration: BoxDecoration(
        color: AppPalette.ok.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.ok.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline_rounded, size: 18, color: AppPalette.ok),
          const SizedBox(width: 8),
          Text('Alert resolved', style: AppText.button.copyWith(color: AppPalette.ok)),
        ],
      ),
    );
  }
}


class _ResolvedToast extends StatelessWidget {
  const _ResolvedToast({
    required this.alertId,
    required this.onClose,
  });

  final String alertId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 390,
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppPalette.ok.withOpacity(0.28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.14),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppPalette.ok.withOpacity(0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                color: AppPalette.ok,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Alert resolved',
                    style: AppText.sectionTitle.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$alertId has been acknowledged and marked as resolved.',
                    style: AppText.caption.copyWith(
                      color: AppPalette.textMuted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(999),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppPalette.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.showProgress = false,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool showProgress;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppPalette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppPalette.blue),
            const SizedBox(height: 16),
            Text(title, style: AppText.sectionTitle),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: AppPalette.textMuted),
            ),
            if (showProgress) ...[
              const SizedBox(height: 18),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              _SmallPrimaryButton(
                icon: Icons.refresh_rounded,
                label: actionLabel!,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AlertItem {
  const AlertItem({
    required this.alertId,
    required this.predictionId,
    required this.alertLevel,
    required this.message,
    required this.createdAt,
    required this.isResolved,
  });

  final int alertId;
  final int? predictionId;
  final String alertLevel;
  final String message;
  final String createdAt;
  final bool isResolved;

  factory AlertItem.fromJson(Map<String, dynamic> json) {
    return AlertItem(
      alertId: _toInt(json['alert_id']) ?? 0,
      predictionId: _toInt(json['prediction_id']),
      alertLevel: (json['alert_level'] ?? 'watch').toString(),
      message: (json['message'] ?? 'No alert message available.').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      isResolved: _toBool(json['is_resolved']),
    );
  }

  AlertItem copyWith({bool? isResolved}) {
    return AlertItem(
      alertId: alertId,
      predictionId: predictionId,
      alertLevel: alertLevel,
      message: message,
      createdAt: createdAt,
      isResolved: isResolved ?? this.isResolved,
    );
  }

  String get displayId => 'ALT-${alertId.toString().padLeft(3, '0')}';

  String get normalizedLevel {
    final value = alertLevel.trim().toLowerCase();
    if (value == 'high') return 'critical';
    if (value == 'medium' || value == 'warning') return 'watch';
    if (value == 'low' || value == 'normal') return 'ok';
    if (value == 'ok' || value == 'watch' || value == 'critical') return value;
    return value.isEmpty ? 'watch' : value;
  }

  String get linkedPredictionText {
    if (predictionId == null) return 'No linked prediction available';
    return 'Linked to prediction #$predictionId';
  }

  String get createdAtText {
    if (createdAt.trim().isEmpty) return 'Unknown time';
    return createdAt.replaceFirst('T', ' ');
  }

  int get createdSortValue => DateTime.tryParse(createdAt)?.millisecondsSinceEpoch ?? alertId;
}

class PredictionDetails {
  const PredictionDetails({
    required this.predictionId,
    required this.engineId,
    required this.cycleId,
    required this.dataTimestep,
    required this.predictedRul,
    required this.status,
    required this.predictedAt,
  });

  final int? predictionId;
  final int? engineId;
  final int? cycleId;
  final int? dataTimestep;
  final num? predictedRul;
  final String status;
  final String predictedAt;

  factory PredictionDetails.fromJson(Map<String, dynamic> json) {
    return PredictionDetails(
      predictionId: _toInt(json['prediction_id']),
      engineId: _toInt(json['engine_id']),
      cycleId: _toInt(json['cycle_id']),
      dataTimestep: _toInt(json['data_timestep']),
      predictedRul: _toNum(json['predicted_rul']),
      status: (json['status'] ?? json['health_status'] ?? '').toString(),
      predictedAt: (json['predicted_at'] ?? '').toString(),
    );
  }

  String get engineLabel => engineId == null ? 'Unknown engine' : 'ENG-$engineId';

  String get rulText {
    if (predictedRul == null) return 'Unavailable';
    final value = predictedRul!;
    final text = value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);
    return '$text cycles';
  }

  String get engineSummary {
    final parts = <String>[];
    parts.add('Engine: $engineLabel');
    if (cycleId != null) parts.add('Cycle: $cycleId');
    parts.add('RUL: $rulText');
    return parts.join('   ·   ');
  }

  String get fullSummary {
    final parts = <String>[];
    parts.add('Engine: $engineLabel');
    if (cycleId != null) parts.add('Cycle ID: $cycleId');
    if (dataTimestep != null) parts.add('Data timestep: $dataTimestep');
    parts.add('Predicted RUL: $rulText');
    if (status.trim().isNotEmpty) parts.add('Status: $status');
    if (predictedAt.trim().isNotEmpty) parts.add('Predicted at: ${predictedAt.replaceFirst('T', ' ')}');
    return parts.join('\n');
  }
}

class _AlertLevelStyle {
  const _AlertLevelStyle({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  factory _AlertLevelStyle.fromLevel(String level) {
    switch (level.toLowerCase()) {
      case 'critical':
        return const _AlertLevelStyle(
          label: 'critical',
          color: AppPalette.critical,
          icon: Icons.warning_amber_rounded,
        );
      case 'ok':
        return const _AlertLevelStyle(
          label: 'ok',
          color: AppPalette.ok,
          icon: Icons.check_circle_outline_rounded,
        );
      case 'watch':
      default:
        return const _AlertLevelStyle(
          label: 'watch',
          color: AppPalette.watch,
          icon: Icons.info_outline_rounded,
        );
    }
  }
}

int? _toInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

num? _toNum(dynamic value) {
  if (value == null) return null;
  if (value is num) return value;
  return num.tryParse(value.toString());
}

bool _toBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value.toString().trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes';
}

class AppPalette {
  static const Color background = Color(0xFFF6F7F9);
  static const Color card = Colors.white;
  static const Color border = Color(0xFFE1E5EA);
  static const Color inputFill = Color(0xFFF2F4F7);
  static const Color navy = Color(0xFF050318);
  static const Color text = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);
  static const Color blue = Color(0xFF2563EB);
  static const Color ok = Color(0xFF22C55E);
  static const Color watch = Color(0xFFF4B400);
  static const Color critical = Color(0xFFF43F46);
}

class AppText {
  static TextStyle get pageTitle => GoogleFonts.inter(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: AppPalette.text,
        letterSpacing: -0.45,
      );

  static TextStyle get sectionTitle => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppPalette.text,
      );

  static TextStyle get metric => GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: AppPalette.text,
      );

  static TextStyle get rowTitle => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: AppPalette.text,
      );

  static TextStyle get body => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppPalette.text,
      );

  static TextStyle get caption => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppPalette.text,
      );

  static TextStyle get tiny => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppPalette.text,
      );

  static TextStyle get badge => GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: AppPalette.text,
      );

  static TextStyle get button => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w800,
      );
}

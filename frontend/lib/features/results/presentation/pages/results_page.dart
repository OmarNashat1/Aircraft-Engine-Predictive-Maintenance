import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:google_fonts/google_fonts.dart';
import 'package:predection_desktop_app/shared/layouts/main_layout.dart';

const String _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

class ResultsPage extends StatefulWidget {
  const ResultsPage({
    super.key,
    this.predictionId,
    this.initialResult,
  });

  final int? predictionId;
  final Map<String, dynamic>? initialResult;

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}


class _ResultRuntimeStore {
  static final Map<int, ResultViewData> _byPredictionId = <int, ResultViewData>{};
  static ResultViewData? _latest;

  static ResultViewData? get latest => _latest;

  static ResultViewData? byPredictionId(int? predictionId) {
    if (predictionId == null) return null;
    return _byPredictionId[predictionId];
  }

  static void save(ResultViewData result) {
    _latest = result;
    final predictionId = result.predictionId;
    if (predictionId != null) {
      _byPredictionId[predictionId] = result;
    }
  }
}

enum _ReportSaveFormat {
  pdf('PDF document', 'pdf'),
  word('Word document', 'doc'),
  text('Text file', 'txt');

  const _ReportSaveFormat(this.label, this.extension);

  final String label;
  final String extension;
}

class _ResultsPageState extends State<ResultsPage> {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _apiBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 120),
      sendTimeout: const Duration(seconds: 120),
    ),
  );

  int _selectedTab = 0;
  bool _isLoading = true;
  bool _isExporting = false;
  bool _isSending = false;
  bool _isSavingReport = false;
  String? _errorMessage;
  ResultViewData? _result;
  SensorTrendData? _trendData;
  FleetHealthCounts? _fleetCounts;
  OverlayEntry? _toastEntry;

  final List<String> _tabs = const [
    'Overview',
    'Reports',
    'Time Series',
    'Explainability',
  ];

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  @override
  void dispose() {
    _toastEntry?.remove();
    _toastEntry = null;
    super.dispose();
  }

  Future<void> _loadPage() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      ResultViewData result;
      final cachedResult = _ResultRuntimeStore.byPredictionId(widget.predictionId) ??
          (widget.predictionId == null ? _ResultRuntimeStore.latest : null);

      if (widget.initialResult != null) {
        result = ResultViewData.fromJson(widget.initialResult!);
      } else if (widget.predictionId != null) {
        try {
          final response = await _dio.get<Map<String, dynamic>>(
            '/results/${widget.predictionId}',
          );
          final data = response.data ?? <String, dynamic>{};
          _throwIfApiError(data);
          result = ResultViewData.fromJson(data);
        } catch (error) {
          if (cachedResult == null) rethrow;
          result = cachedResult;
        }
      } else if (cachedResult != null) {
        result = cachedResult;
      } else {
        throw Exception(
          'No prediction result is available yet. Run a prediction or open a saved result from History.',
        );
      }

      SensorTrendData? trendData;
      final trendPredictionId = result.predictionId ?? widget.predictionId;
      if (trendPredictionId != null) {
        try {
          final trendResponse = await _dio.get<Map<String, dynamic>>(
            '/results/$trendPredictionId/decreasing-sensor-trends',
          );
          final trendJson = trendResponse.data ?? <String, dynamic>{};
          if (!trendJson.containsKey('error')) {
            trendData = SensorTrendData.fromJson(trendJson);
          }
        } catch (_) {
          trendData = null;
        }
      }

      if (result.engineId != null && result.cycleId != null) {
        try {
          final sensorResponse = await _dio.get<Map<String, dynamic>>(
            '/analytics/sensor-groups',
            queryParameters: {
              'engine_id': result.engineId,
              'cycle_id': result.cycleId,
            },
          );
          final sensorJson = sensorResponse.data ?? <String, dynamic>{};
          if (!sensorJson.containsKey('error')) {
            result = result.withFeatureReadings(
              _latestValuesFromSensorGroups(sensorJson),
            );
          }
        } catch (_) {
          // The page can still render without raw sensor values.
        }
      }

      FleetHealthCounts? fleetCounts;
      try {
        final summaryResponse = await _dio.get<Map<String, dynamic>>(
          '/dashboard-summary',
        );
        final summaryJson = summaryResponse.data ?? <String, dynamic>{};
        if (!summaryJson.containsKey('error')) {
          fleetCounts = FleetHealthCounts.fromJson(summaryJson);
        }
      } catch (_) {
        // Interactivity still works with probability-only labels if fleet counts are unavailable.
      }

      _ResultRuntimeStore.save(result);

      if (!mounted) return;
      setState(() {
        _result = result;
        _trendData = trendData;
        _fleetCounts = fleetCounts;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _throwIfApiError(Map<String, dynamic> data) {
    if (data.containsKey('error')) {
      throw Exception(data['error']);
    }
  }

  void _showTemplatePopup({
    required String title,
    required String message,
    bool isError = false,
  }) {
    _toastEntry?.remove();
    _toastEntry = null;

    final overlay = Overlay.of(context);
    final accentColor = isError ? AppPalette.red : AppPalette.green;
    final backgroundColor = isError ? const Color(0xFFFFF1F2) : const Color(0xFFEFFBF4);
    final borderColor = isError ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0);
    final icon = isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          right: 24,
          bottom: 24,
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 190),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset((1 - value) * 16, 0),
                    child: child,
                  ),
                );
              },
              child: Container(
                width: 350,
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                decoration: BoxDecoration(
                  color: AppPalette.cardBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: accentColor, size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: AppText.body.copyWith(
                              color: AppPalette.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            message,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
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
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        entry.remove();
                        if (identical(_toastEntry, entry)) _toastEntry = null;
                      },
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
            ),
          ),
        );
      },
    );

    _toastEntry = entry;
    overlay.insert(entry);

    Future<void>.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      if (identical(_toastEntry, entry)) {
        entry.remove();
        _toastEntry = null;
      }
    });
  }

  Future<void> _exportPdf() async {
    final predictionId = _result?.predictionId ?? widget.predictionId;
    if (predictionId == null || _isExporting) return;

    setState(() => _isExporting = true);

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/export-report',
        queryParameters: {'prediction_id': predictionId},
      );
      final data = response.data ?? <String, dynamic>{};
      _throwIfApiError(data);

      if (!mounted) return;
      final pdfPath = data['pdf_path']?.toString() ?? 'reports folder';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF exported successfully: $pdfPath'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: ${error.toString()}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _saveReport() async {
    final result = _result;
    if (result == null || _isSavingReport) return;

    final format = await _chooseReportFormat();
    if (format == null) return;

    setState(() => _isSavingReport = true);

    try {
      final defaultName = _defaultReportFileName(result, format);
      final selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save engine health report as ${format.label}',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: [format.extension],
      );

      if (selectedPath == null) return;

      final outputPath = _ensureExtension(selectedPath, format.extension);
      final sections = _ReportSections.fromResult(result);
      await _writeReportFile(
        outputPath: outputPath,
        format: format,
        result: result,
        sections: sections,
      );

      if (!mounted) return;
      _showTemplatePopup(
        title: 'Report saved',
        message: 'The ${format.extension.toUpperCase()} report was saved successfully.',
      );
    } catch (error) {
      if (!mounted) return;
      _showTemplatePopup(
        title: 'Save failed',
        message: error.toString(),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSavingReport = false);
    }
  }

  Future<_ReportSaveFormat?> _chooseReportFormat() {
    return showDialog<_ReportSaveFormat>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Save report as'),
          content: const Text('Choose the format you want to save this report in.'),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(_ReportSaveFormat.text),
              icon: const Icon(Icons.article_outlined, size: 18),
              label: const Text('TXT'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(_ReportSaveFormat.word),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('Word'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(_ReportSaveFormat.pdf),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('PDF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.primaryBlack,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  String _defaultReportFileName(ResultViewData result, _ReportSaveFormat format) {
    final engine = result.engineId?.toString() ?? 'unknown_engine';
    final cycle = result.cycleId?.toString() ?? 'unknown_cycle';
    final prediction = result.predictionId?.toString() ?? 'latest';
    return 'engine_health_report_engine_${engine}_cycle_${cycle}_prediction_$prediction.${format.extension}';
  }

  String _ensureExtension(String selectedPath, String extension) {
    final normalized = selectedPath.toLowerCase();
    final requiredExtension = '.$extension';
    if (normalized.endsWith(requiredExtension)) return selectedPath;
    return '$selectedPath$requiredExtension';
  }

  Future<void> _writeReportFile({
    required String outputPath,
    required _ReportSaveFormat format,
    required ResultViewData result,
    required _ReportSections sections,
  }) async {
    switch (format) {
      case _ReportSaveFormat.pdf:
        final bytes = await _buildPdfReport(result, sections);
        await File(outputPath).writeAsBytes(bytes, flush: true);
        return;
      case _ReportSaveFormat.word:
        await File(outputPath).writeAsString(
          _buildWordCompatibleReport(result, sections),
          encoding: utf8,
          flush: true,
        );
        return;
      case _ReportSaveFormat.text:
        await File(outputPath).writeAsString(
          _buildPlainTextReport(result, sections),
          encoding: utf8,
          flush: true,
        );
        return;
    }
  }



  String _pdfSafe(String value) {
    return value
        .replaceAll('\u00a0', ' ')
        .replaceAll('\u202f', ' ')
        .replaceAll('\u2007', ' ')
        .replaceAll('\u2009', ' ')
        .replaceAll('\u200a', ' ')
        .replaceAll('\u200b', '')
        .replaceAll('\u2060', '')
        .replaceAll('\ufeff', '')
        .replaceAll('\u2010', '-')
        .replaceAll('\u2011', '-')
        .replaceAll('\u2012', '-')
        .replaceAll('\u2013', '-')
        .replaceAll('\u2014', '-')
        .replaceAll('\u2212', '-')
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('\u201c', '"')
        .replaceAll('\u201d', '"')
        .replaceAll('\u2026', '...')
        .replaceAll('\u2248', 'approximately')
        .replaceAll('\u2264', '<=')
        .replaceAll('\u2265', '>=')
        .replaceAll('•', '-')
        .replaceAll('≈', 'approximately')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('‑', '-')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('’', "'")
        .replaceAll('‘', "'");
  }

  Future<List<int>> _buildPdfReport(ResultViewData result, _ReportSections sections) async {
    final pdf = pw.Document();
    final metaRows = _reportMetadataRows(result);

    List<pw.Widget> sectionBodyWidgets(String body) {
      final widgets = <pw.Widget>[];
      final safeBody = _pdfSafe(body.trim());

      for (final rawLine in safeBody.split('\n')) {
        final line = rawLine.trim();

        if (line.isEmpty) {
          widgets.add(pw.SizedBox(height: 6));
          continue;
        }

        widgets.add(
          pw.Text(
            line,
            textAlign: pw.TextAlign.justify,
            style: const pw.TextStyle(fontSize: 11),
          ),
        );
        widgets.add(pw.SizedBox(height: 3));
      }

      return widgets;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(55, 50, 55, 60),
        build: (context) => [
          pw.Text(
            'Engine Health Analysis Report',
            style: pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 35),
          for (final row in metaRows) ...[
            pw.Text(
              '${_pdfSafe(row.key)}: ${_pdfSafe(row.value)}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 8),
          ],
          pw.SizedBox(height: 18),
          pw.Text(
            'Maintenance Report',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 26),
          for (final section in sections.items) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              _pdfSafe(section.title),
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            ...sectionBodyWidgets(section.body),
            pw.SizedBox(height: 6),
          ],
        ],
      ),
    );

    return pdf.save();
  }


  String _buildWordCompatibleReport(ResultViewData result, _ReportSections sections) {
    final metaRows = _reportMetadataRows(result);
    final rowsHtml = metaRows.map((row) {
      return '<tr><th>${_escapeHtml(row.key)}</th><td>${_escapeHtml(row.value)}</td></tr>';
    }).join();

    final sectionsHtml = sections.items.map((section) {
      final bodyHtml = _escapeHtml(section.body.trim()).replaceAll(RegExp(r'\r?\n'), '<br>');
      return '''
        <h2>${_escapeHtml(section.title)}</h2>
        <p>$bodyHtml</p>
      ''';
    }).join('\n');

    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Engine Health Analysis Report</title>
<style>
  body { font-family: Arial, sans-serif; font-size: 11pt; color: #101828; line-height: 1.55; }
  h1 { font-size: 20pt; margin-bottom: 18px; }
  h2 { font-size: 13pt; margin-top: 22px; margin-bottom: 8px; }
  table { border-collapse: collapse; margin-bottom: 20px; width: 100%; }
  th, td { border: 1px solid #d9dee8; padding: 7px 9px; text-align: left; vertical-align: top; }
  th { width: 170px; background: #f5f7fb; }
  p { margin-top: 0; text-align: justify; }
</style>
</head>
<body>
<h1>Engine Health Analysis Report</h1>
<table>$rowsHtml</table>
$sectionsHtml
</body>
</html>
''';
  }

  String _buildPlainTextReport(ResultViewData result, _ReportSections sections) {
    final buffer = StringBuffer();
    buffer.writeln('Engine Health Analysis Report');
    buffer.writeln();

    for (final row in _reportMetadataRows(result)) {
      buffer.writeln('${row.key}: ${row.value}');
    }

    buffer.writeln();

    for (final section in sections.items) {
      buffer.writeln(section.title);
      buffer.writeln(section.body.trim());
      buffer.writeln();
    }

    return buffer.toString().trimRight() + '\n';
  }

  List<MapEntry<String, String>> _reportMetadataRows(ResultViewData result) {
    return [
      MapEntry('Prediction ID', result.predictionId?.toString() ?? '-'),
      MapEntry('Engine ID', result.engineId?.toString() ?? '-'),
      MapEntry('Cycle ID', result.cycleId?.toString() ?? '-'),
      MapEntry('Data Timestep', result.dataTimestep?.toString() ?? '-'),
      MapEntry('Predicted RUL', '${result.predictedRulText} cycles'),
      MapEntry('Status', _titleCase(normalizeStatus(result.status))),
      MapEntry('Prediction Time', result.predictedAt ?? '-'),
    ];
  }

  String _escapeHtml(String value) {
    return const HtmlEscape(HtmlEscapeMode.element).convert(value);
  }

  Future<List<String>> _loadMaintenanceRecipients() async {
    try {
      final env = Platform.environment;
      final String basePath;

      if (Platform.isWindows && (env['APPDATA'] ?? '').isNotEmpty) {
        basePath = env['APPDATA']!;
      } else if ((env['HOME'] ?? '').isNotEmpty) {
        basePath = env['HOME']!;
      } else {
        basePath = Directory.current.path;
      }

      final file = File(
        '$basePath${Platform.pathSeparator}EngineHealthMonitor${Platform.pathSeparator}settings.json',
      );

      if (!await file.exists()) {
        return const <String>[];
      }

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return const <String>[];
      }

      final values = decoded['maintenanceRecipients'];
      if (values is! List) {
        return const <String>[];
      }

      return values
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _sendToMaintenance() async {
    final predictionId = _result?.predictionId ?? widget.predictionId;
    if (predictionId == null || _isSending) return;

    setState(() => _isSending = true);

    try {
      final recipients = await _loadMaintenanceRecipients();

      final response = await _dio.post<Map<String, dynamic>>(
        '/send-to-maintenance/$predictionId',
        data: <String, dynamic>{
          'recipient_emails': recipients.isEmpty ? null : recipients,
          'cc_emails': null,
        },
      );
      final data = response.data ?? <String, dynamic>{};
      _throwIfApiError(data);

      if (!mounted) return;
      final sentToRaw = data['sent_to'];
      final sentTo = sentToRaw is List
          ? sentToRaw.map((item) => item.toString()).where((item) => item.isNotEmpty).join(', ')
          : '';

      _showTemplatePopup(
        title: 'Email sent',
        message: sentTo.isEmpty
            ? 'Report PDF was sent to maintenance successfully.'
            : 'Report PDF was sent to $sentTo.',
      );
    } catch (error) {
      if (!mounted) return;
      _showTemplatePopup(
        title: 'Send failed',
        message: error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      currentRoute: '/results',
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2.4),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: _ErrorPanel(
          message: _errorMessage!,
          onRetry: _loadPage,
        ),
      );
    }

    final result = _result;
    if (result == null) {
      return Center(
        child: _ErrorPanel(
          message: 'No prediction result is available.',
          onRetry: _loadPage,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1026),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Results',
                style: GoogleFonts.inter(
                  fontSize: 28,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              _ResultSummaryHeader(result: result),
              const SizedBox(height: 20),
              _OverviewActionSlot(
                visible: _selectedTab == 0,
                child: _OverviewActions(
                  canUseActions: result.predictionId != null || widget.predictionId != null,
                  isExporting: _isExporting,
                  isSending: _isSending,
                  onExportPdf: _exportPdf,
                  onSendToMaintenance: _sendToMaintenance,
                ),
              ),
              _SegmentedTabs(
                tabs: _tabs,
                selectedIndex: _selectedTab,
                onChanged: (index) => setState(() => _selectedTab = index),
              ),
              const SizedBox(height: 8),
              _ResultTabSwitcher(
                selectedIndex: _selectedTab,
                result: result,
                trendData: _trendData,
                fleetCounts: _fleetCounts,
                isSavingReport: _isSavingReport,
                onSaveReport: _saveReport,
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _ResultTabSwitcher extends StatefulWidget {
  const _ResultTabSwitcher({
    required this.selectedIndex,
    required this.result,
    required this.trendData,
    required this.fleetCounts,
    required this.isSavingReport,
    required this.onSaveReport,
  });

  final int selectedIndex;
  final ResultViewData result;
  final SensorTrendData? trendData;
  final FleetHealthCounts? fleetCounts;
  final bool isSavingReport;
  final VoidCallback onSaveReport;

  @override
  State<_ResultTabSwitcher> createState() => _ResultTabSwitcherState();
}

class _ResultTabSwitcherState extends State<_ResultTabSwitcher> {
  final Map<int, Widget> _pageCache = <int, Widget>{};
  int? _lastPredictionId;
  int? _lastTrendLength;
  double? _lastRul;
  String? _lastFleetSignature;

  @override
  void initState() {
    super.initState();
    _rememberCurrentData();
  }

  @override
  void didUpdateWidget(covariant _ResultTabSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);

    final predictionChanged = _lastPredictionId != widget.result.predictionId;
    final rulChanged = _lastRul != widget.result.predictedRul;
    final trendChanged = _lastTrendLength != widget.trendData?.series.length;
    final saveStateChanged = oldWidget.isSavingReport != widget.isSavingReport;
    final fleetChanged = _lastFleetSignature != widget.fleetCounts?.signature;

    if (predictionChanged || rulChanged || trendChanged || saveStateChanged || fleetChanged) {
      _pageCache.clear();
      _rememberCurrentData();
    }
  }

  void _rememberCurrentData() {
    _lastPredictionId = widget.result.predictionId;
    _lastRul = widget.result.predictedRul;
    _lastTrendLength = widget.trendData?.series.length;
    _lastFleetSignature = widget.fleetCounts?.signature;
  }

  @override
  Widget build(BuildContext context) {
    final page = _pageFor(widget.selectedIndex);

    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        key: ValueKey<int>(widget.selectedIndex),
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 135),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1 - value) * 6),
              child: child,
            ),
          );
        },
        child: page,
      ),
    );
  }

  Widget _pageFor(int index) {
    return _pageCache.putIfAbsent(index, () {
      switch (index) {
        case 0:
          return OverviewTab(
            key: const ValueKey('overview-tab-cache'),
            result: widget.result,
            fleetCounts: widget.fleetCounts,
          );
        case 1:
          return ReportsTab(
            key: const ValueKey('reports-tab-cache'),
            result: widget.result,
            isSavingReport: widget.isSavingReport,
            onSaveReport: widget.onSaveReport,
          );
        case 2:
          return TimeSeriesTab(
            key: const ValueKey('time-series-tab-cache'),
            result: widget.result,
            trendData: widget.trendData,
          );
        case 3:
          return ExplainabilityTab(
            key: const ValueKey('explainability-tab-cache'),
            result: widget.result,
          );
        default:
          return const SizedBox.shrink();
      }
    });
  }
}

class OverviewTab extends StatelessWidget {
  const OverviewTab({
    super.key,
    required this.result,
    required this.fleetCounts,
  });

  final ResultViewData result;
  final FleetHealthCounts? fleetCounts;

  @override
  Widget build(BuildContext context) {
    final probabilities = HealthProbabilities.fromStatus(result.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 850;
            final probabilityCard = _WhiteCard(
              child: HealthClassificationCard(
                probabilities: probabilities,
                fleetCounts: fleetCounts,
              ),
            );
            final featuresCard = _WhiteCard(
              child: TopFeaturesCard(
                features: result.topFeatures.take(5).toList(),
                featureValues: result.featureReadings,
              ),
            );

            if (isNarrow) {
              return Column(
                children: [
                  probabilityCard,
                  const SizedBox(height: 20),
                  featuresCard,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: probabilityCard),
                const SizedBox(width: 20),
                Expanded(child: featuresCard),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        _RecommendationPanel(result: result),
      ],
    );
  }
}

class ReportsTab extends StatelessWidget {
  const ReportsTab({
    super.key,
    required this.result,
    required this.isSavingReport,
    required this.onSaveReport,
  });

  final ResultViewData result;
  final bool isSavingReport;
  final VoidCallback onSaveReport;

  @override
  Widget build(BuildContext context) {
    final sections = _ReportSections.fromResult(result);

    return _WhiteCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.description_outlined,
                size: 18,
                color: AppPalette.blue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Engine Health Analysis Report',
                  style: AppText.body.copyWith(
                    color: AppPalette.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _ActionButton(
                label: isSavingReport ? 'Saving...' : 'Save Report',
                icon: Icons.save_alt_outlined,
                isEnabled: !isSavingReport,
                onPressed: onSaveReport,
              ),
            ],
          ),
          const SizedBox(height: 42),
          ...sections.items.map(
            (section) => Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: _ReportSectionBlock(section: section),
            ),
          ),
        ],
      ),
    );
  }
}

class TimeSeriesTab extends StatelessWidget {
  const TimeSeriesTab({
    super.key,
    required this.result,
    required this.trendData,
  });

  final ResultViewData result;
  final SensorTrendData? trendData;

  @override
  Widget build(BuildContext context) {
    final trend = trendData;

    return _WhiteCard(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Sensor Trends Across Cycle ${result.cycleId?.toString() ?? '-'}",
            style: AppText.body.copyWith(
              color: AppPalette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 28),
          if (trend == null || trend.series.isEmpty || trend.features.isEmpty)
            SizedBox(
              height: 330,
              child: _EmptyState(
                title: 'No decreasing sensor trends available',
                message: 'The backend did not return trend data for this prediction. The RUL and status are still shown above.',
              ),
            )
          else
            _TrendChart(trendData: trend),
        ],
      ),
    );
  }
}

class ExplainabilityTab extends StatelessWidget {
  const ExplainabilityTab({super.key, required this.result});

  final ResultViewData result;

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Feature Importance (SHAP Values)',
            style: AppText.body.copyWith(
              color: AppPalette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 38),
          if (result.topFeatures.isEmpty)
            const SizedBox(
              height: 260,
              child: _EmptyState(
                title: 'No feature importance data available',
                message: 'The prediction response did not include feature contributions.',
              ),
            )
          else
            FeatureImportanceBars(features: result.topFeatures.take(8).toList()),
        ],
      ),
    );
  }
}

class _ResultSummaryHeader extends StatelessWidget {
  const _ResultSummaryHeader({required this.result});

  final ResultViewData result;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 108),
      padding: const EdgeInsets.fromLTRB(22, 18, 28, 18),
      decoration: BoxDecoration(
        color: AppPalette.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Status', style: AppText.smallLabel),
                const SizedBox(height: 8),
                StatusPill(status: result.status),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Predicted RUL', style: AppText.smallLabel),
                const SizedBox(height: 8),
                Text(
                  '${result.predictedRulText} cycles',
                  style: AppText.rulValue,
                ),
                const SizedBox(height: 4),
                Text(
                  result.intervalText,
                  style: AppText.caption.copyWith(color: AppPalette.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewActionSlot extends StatelessWidget {
  const _OverviewActionSlot({
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOutCubic,
      height: visible ? 51 : 4,
      width: double.infinity,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : const Offset(0, -0.08),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          opacity: visible ? 1 : 0,
          child: IgnorePointer(
            ignoring: !visible,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Align(
                alignment: Alignment.topLeft,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverviewActions extends StatelessWidget {
  const _OverviewActions({
    required this.canUseActions,
    required this.isExporting,
    required this.isSending,
    required this.onExportPdf,
    required this.onSendToMaintenance,
  });

  final bool canUseActions;
  final bool isExporting;
  final bool isSending;
  final VoidCallback onExportPdf;
  final VoidCallback onSendToMaintenance;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ActionButton(
          label: isExporting ? 'Exporting...' : 'Export PDF',
          icon: Icons.file_download_outlined,
          isPrimary: true,
          isEnabled: canUseActions && !isExporting,
          onPressed: onExportPdf,
        ),
        const SizedBox(width: 10),
        _ActionButton(
          label: isSending ? 'Sending...' : 'Send to Maintenance',
          icon: Icons.send_outlined,
          isEnabled: canUseActions && !isSending,
          onPressed: onSendToMaintenance,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isPrimary = false,
    this.isEnabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isPrimary;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    final background = isPrimary ? AppPalette.primaryBlack : AppPalette.cardBackground;
    final foreground = isPrimary ? Colors.white : AppPalette.textPrimary;
    final border = isPrimary ? AppPalette.primaryBlack : AppPalette.border;

    return SizedBox(
      height: 31,
      child: ElevatedButton.icon(
        onPressed: isEnabled ? onPressed : null,
        icon: Icon(icon, size: 15),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: isPrimary ? AppPalette.primaryBlack.withOpacity(0.55) : AppPalette.cardBackground,
          disabledForegroundColor: foreground.withOpacity(0.55),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: AppText.button,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: border),
          ),
        ),
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 31,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppPalette.tabBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < tabs.length; index++)
            _TabChip(
              label: tabs[index],
              isSelected: index == selectedIndex,
              onTap: () => onChanged(index),
            ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        height: 25,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? AppPalette.cardBackground : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: AppText.tab.copyWith(
            color: AppPalette.textPrimary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class HealthClassificationCard extends StatefulWidget {
  const HealthClassificationCard({
    super.key,
    required this.probabilities,
    required this.fleetCounts,
  });

  final HealthProbabilities probabilities;
  final FleetHealthCounts? fleetCounts;

  @override
  State<HealthClassificationCard> createState() => _HealthClassificationCardState();
}

class _HealthClassificationCardState extends State<HealthClassificationCard> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _touchedIndex.clamp(-1, 2).toInt();
    final centerLabel = _centerLabel(selectedIndex);

    return SizedBox(
      height: 390,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Health Classification',
            style: AppText.sectionTitle,
          ),
          Expanded(
            child: Center(
              child: MouseRegion(
                onExit: (_) => setState(() => _touchedIndex = -1),
                child: SizedBox(
                  width: 230,
                  height: 230,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          startDegreeOffset: -88,
                          centerSpaceRadius: 54,
                          sectionsSpace: 5,
                          borderData: FlBorderData(show: false),
                          pieTouchData: PieTouchData(
                            enabled: true,
                            touchCallback: (event, response) {
                              if (!event.isInterestedForInteractions ||
                                  response == null ||
                                  response.touchedSection == null) {
                                if (_touchedIndex != -1) {
                                  setState(() => _touchedIndex = -1);
                                }
                                return;
                              }

                              final nextIndex = response.touchedSection!.touchedSectionIndex;
                              if (nextIndex != _touchedIndex) {
                                setState(() => _touchedIndex = nextIndex);
                              }
                            },
                          ),
                          sections: [
                            _pieSection(
                              index: 0,
                              value: widget.probabilities.normal,
                              color: AppPalette.green,
                            ),
                            _pieSection(
                              index: 1,
                              value: widget.probabilities.watch,
                              color: AppPalette.amber,
                            ),
                            _pieSection(
                              index: 2,
                              value: widget.probabilities.critical,
                              color: AppPalette.red,
                            ),
                          ],
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 120),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              centerLabel.title,
                              textAlign: TextAlign.center,
                              style: AppText.body.copyWith(
                                color: AppPalette.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (centerLabel.subtitle.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                centerLabel.subtitle,
                                textAlign: TextAlign.center,
                                style: AppText.caption.copyWith(
                                  color: AppPalette.textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Wrap(
              spacing: 14,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _HealthCountLegendDot(
                  label: 'OK: ${_countText(widget.fleetCounts?.ok)}',
                  color: AppPalette.green,
                ),
                _HealthCountLegendDot(
                  label: 'Watch: ${_countText(widget.fleetCounts?.watch)}',
                  color: AppPalette.amber,
                ),
                _HealthCountLegendDot(
                  label: 'Critical: ${_countText(widget.fleetCounts?.critical)}',
                  color: AppPalette.red,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _countText(int? count) {
    if (count == null) return '--';
    return '$count ${count == 1 ? 'engine' : 'engines'}';
  }

  PieChartSectionData _pieSection({
    required int index,
    required double value,
    required Color color,
  }) {
    final isTouched = index == _touchedIndex;

    return PieChartSectionData(
      value: value,
      color: color,
      title: '',
      radius: isTouched ? 39 : 34,
    );
  }

  _HealthSliceLabel _centerLabel(int index) {
    if (index < 0) {
      final total = widget.fleetCounts?.total;
      return _HealthSliceLabel(
        title: total == null ? 'Engines' : '$total ${total == 1 ? 'engine' : 'engines'}',
        subtitle: '',
      );
    }

    final counts = [
      widget.fleetCounts?.ok,
      widget.fleetCounts?.watch,
      widget.fleetCounts?.critical,
    ];

    const labels = ['OK', 'Watch', 'Critical'];
    final count = counts[index];

    return _HealthSliceLabel(
      title: count == null ? 'Engines' : '$count ${count == 1 ? 'engine' : 'engines'}',
      subtitle: labels[index],
    );
  }
}


class _HealthSliceLabel {
  const _HealthSliceLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
}

class _HealthCountLegendDot extends StatelessWidget {
  const _HealthCountLegendDot({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

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
          style: AppText.caption.copyWith(
            color: AppPalette.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class TopFeaturesCard extends StatelessWidget {
  const TopFeaturesCard({
    super.key,
    required this.features,
    required this.featureValues,
  });

  final List<FeatureContribution> features;
  final Map<String, double> featureValues;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 410,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top 5 Contributing Features (SHAP)',
            style: AppText.body.copyWith(
              color: AppPalette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 30),
          if (features.isEmpty)
            const Expanded(
              child: _EmptyState(
                title: 'No contributing features',
                message: 'Feature contribution data was not returned for this prediction.',
              ),
            )
          else
            Expanded(
              child: Column(
                children: [
                  for (final feature in features) ...[
                    _FeatureContributionTile(
                      feature: feature,
                      sensorValue: featureValues[feature.feature] ??
                          featureValues[feature.displayName] ??
                          feature.rawReading,
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FeatureContributionTile extends StatelessWidget {
  const _FeatureContributionTile({
    required this.feature,
    required this.sensorValue,
  });

  final FeatureContribution feature;
  final double? sensorValue;

  @override
  Widget build(BuildContext context) {
    final valuePrefix = feature.shapValue >= 0 ? '+' : '';
    final readingText = sensorValue == null
        ? 'Not available'
        : _formatCompact(sensorValue!);

    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppPalette.softCard,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        feature.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(
                          color: AppPalette.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _RiskChip(level: feature.priorityLabel),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Value: $readingText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: AppPalette.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$valuePrefix${_formatCompact(feature.shapValue)}',
            style: AppText.body.copyWith(
              color: feature.shapValue >= 0 ? AppPalette.blue : AppPalette.red,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationPanel extends StatelessWidget {
  const _RecommendationPanel({required this.result});

  final ResultViewData result;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 11, 16, 12),
      decoration: BoxDecoration(
        color: AppPalette.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.trending_up,
            size: 16,
            color: AppPalette.primaryBlack,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recommendation:',
                  style: AppText.caption.copyWith(
                    color: AppPalette.textMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  result.recommendationText,
                  style: AppText.caption.copyWith(
                    color: AppPalette.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportSectionBlock extends StatelessWidget {
  const _ReportSectionBlock({required this.section});

  final ReportSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(section.title, style: AppText.reportHeading),
        const SizedBox(height: 12),
        Text(
          section.body,
          style: AppText.reportBody,
        ),
      ],
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.trendData});

  final SensorTrendData trendData;

  static const List<Color> _seriesColors = [
    AppPalette.red,
    AppPalette.amber,
    AppPalette.blue,
    AppPalette.green,
    AppPalette.purple,
    AppPalette.teal,
  ];

  @override
  Widget build(BuildContext context) {
    final requestedFeatures = trendData.features.take(6).toList();
    final visibleFeatures = <String>[];
    final lineBars = <LineChartBarData>[];
    final maxX = math.max(0, trendData.series.length - 1).toDouble();
    final bottomInterval = maxX <= 0 ? 1.0 : maxX / 4.0;

    for (final feature in requestedFeatures) {
      final color = _seriesColors[visibleFeatures.length % _seriesColors.length];
      final spots = trendData.normalizedSpotsFor(feature);
      if (spots.isEmpty) continue;

      visibleFeatures.add(feature);
      lineBars.add(
        LineChartBarData(
          spots: spots,
          isCurved: false,
          color: color,
          barWidth: 2.2,
          dotData: const FlDotData(show: false),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 330,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 28, 0),
            child: RepaintBoundary(
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: maxX,
                  minY: 0,
                  maxY: 1,
                  lineBarsData: lineBars,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: 0.25,
                    verticalInterval: bottomInterval,
                    getDrawingHorizontalLine: (_) => const FlLine(
                      color: AppPalette.chartGrid,
                      strokeWidth: 1,
                      dashArray: [3, 3],
                    ),
                    getDrawingVerticalLine: (_) => const FlLine(
                      color: AppPalette.chartGrid,
                      strokeWidth: 1,
                      dashArray: [3, 3],
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        interval: 0.25,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${(value * 100).round()}',
                            style: AppText.axis,
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      axisNameWidget: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Cycle progress',
                          style: AppText.caption.copyWith(color: AppPalette.textMuted),
                        ),
                      ),
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        interval: bottomInterval,
                        getTitlesWidget: (value, meta) {
                          if (maxX <= 0) return const SizedBox.shrink();
                          final percent = (value / maxX * 100).round().clamp(0, 100);
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '$percent%',
                              style: AppText.axis,
                            ),
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
                      right: BorderSide(color: AppPalette.axisBorder),
                      top: BorderSide(color: Colors.transparent),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      getTooltipItems: (spots) {
                        return spots.map((spot) {
                          final barIndex = spot.barIndex;
                          final feature = barIndex >= 0 && barIndex < visibleFeatures.length
                              ? visibleFeatures[barIndex]
                              : '';
                          final actual = trendData.rawValueAt(feature, spot.x.round());
                          final progress = maxX <= 0 ? 0 : (spot.x / maxX * 100).round().clamp(0, 100);
                          return LineTooltipItem(
                            '$feature\nCycle progress: $progress%\nValue: ${_formatCompact(actual)}',
                            AppText.caption.copyWith(
                              color: AppPalette.cardBackground,
                              fontWeight: FontWeight.w700,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 8,
          children: [
            for (var index = 0; index < visibleFeatures.length; index++)
              _LegendDot(
                label: _displayFeatureName(visibleFeatures[index]),
                color: _seriesColors[index % _seriesColors.length],
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Values are normalized per feature across the selected engine cycle. Hover the line to see the raw sensor value.',
          style: AppText.caption.copyWith(color: AppPalette.textMuted),
        ),
      ],
    );
  }
}

class FeatureImportanceBars extends StatelessWidget {
  const FeatureImportanceBars({super.key, required this.features});

  final List<FeatureContribution> features;

  @override
  Widget build(BuildContext context) {
    final maxValue = features.fold<double>(
      0,
      (previous, feature) => math.max(previous, feature.absShapValue),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
      child: Column(
        children: [
          for (var index = 0; index < features.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _HorizontalImportanceBar(
                feature: features[index],
                maxValue: maxValue <= 0 ? 1 : maxValue,
              ),
            ),
          const SizedBox(height: 8),
          _ImportanceAxis(maxValue: maxValue <= 0 ? 1 : maxValue),
        ],
      ),
    );
  }
}

class _HorizontalImportanceBar extends StatefulWidget {
  const _HorizontalImportanceBar({
    required this.feature,
    required this.maxValue,
  });

  final FeatureContribution feature;
  final double maxValue;

  @override
  State<_HorizontalImportanceBar> createState() => _HorizontalImportanceBarState();
}

class _HorizontalImportanceBarState extends State<_HorizontalImportanceBar> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final feature = widget.feature;
    final fraction = (feature.absShapValue / widget.maxValue).clamp(0.02, 1.0);
    final importanceText = feature.importancePercent > 0
        ? '${_formatCompact(feature.importancePercent)}%'
        : _formatCompact(feature.absShapValue);
    final signedPrefix = feature.shapValue >= 0 ? '+' : '';
    final shapText = 'SHAP $signedPrefix${_formatCompact(feature.shapValue)}';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              feature.displayName,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.axis.copyWith(
                fontSize: 12,
                fontWeight: _isHovered ? FontWeight.w800 : FontWeight.w600,
                color: _isHovered ? AppPalette.textPrimary : AppPalette.axisText,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const chipWidth = 78.0;
                final usableWidth = math.max(1.0, constraints.maxWidth - chipWidth - 14);
                final barWidth = math.max(34.0, usableWidth * fraction);
                final chipLeft = math.min(
                  constraints.maxWidth - chipWidth,
                  math.max(0.0, barWidth + 10),
                );

                return SizedBox(
                  height: 58,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOutCubic,
                        width: barWidth,
                        height: _isHovered ? 38 : 34,
                        decoration: BoxDecoration(
                          color: AppPalette.blue.withOpacity(_isHovered ? 0.98 : 0.90),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: _isHovered
                              ? [
                                  BoxShadow(
                                    color: AppPalette.blue.withOpacity(0.18),
                                    blurRadius: 14,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOutCubic,
                        left: chipLeft,
                        child: _ImportanceChip(
                          text: importanceText,
                          isHovered: _isHovered,
                          positive: feature.shapValue >= 0,
                        ),
                      ),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: _isHovered ? 1 : 0,
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Container(
                            margin: const EdgeInsets.only(left: 8, bottom: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppPalette.cardBackground.withOpacity(0.96),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: AppPalette.border),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              shapText,
                              style: AppText.caption.copyWith(
                                color: feature.shapValue >= 0 ? AppPalette.blue : AppPalette.red,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportanceChip extends StatelessWidget {
  const _ImportanceChip({
    required this.text,
    required this.isHovered,
    required this.positive,
  });

  final String text;
  final bool isHovered;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final chipColor = isHovered
        ? (positive ? AppPalette.blue : AppPalette.red)
        : AppPalette.cardBackground;
    final textColor = isHovered ? Colors.white : AppPalette.textPrimary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 74,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isHovered
              ? (positive ? AppPalette.blue : AppPalette.red)
              : AppPalette.border,
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.caption.copyWith(
          color: textColor,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ImportanceAxis extends StatelessWidget {
  const _ImportanceAxis({required this.maxValue});

  final double maxValue;

  @override
  Widget build(BuildContext context) {
    final ticks = <double>[
      0,
      maxValue * 0.25,
      maxValue * 0.5,
      maxValue * 0.75,
      maxValue,
    ];

    return Padding(
      padding: const EdgeInsets.only(left: 102, right: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: ticks
            .map(
              (tick) => Text(
                _formatAxisTick(tick),
                style: AppText.axis,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.border),
      ),
      child: child,
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeStatus(status);
    final color = _statusColor(normalized);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        _titleCase(normalized),
        style: AppText.badge.copyWith(color: Colors.white),
      ),
    );
  }
}

class _RiskChip extends StatelessWidget {
  const _RiskChip({required this.level});

  final String level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppPalette.cardBackground,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppPalette.border),
      ),
      child: Text(
        level,
        style: AppText.chip,
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.label, required this.color});

  final String label;
  final Color color;

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
        Text(label, style: AppText.caption.copyWith(color: AppPalette.textPrimary)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.info_outline, size: 28, color: AppPalette.textMuted),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(
                color: AppPalette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(color: AppPalette.textMuted, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 460,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppPalette.red, size: 30),
          const SizedBox(height: 12),
          Text(
            'Unable to load results',
            style: AppText.sectionTitle,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(color: AppPalette.textMuted, height: 1.4),
          ),
          const SizedBox(height: 16),
          _ActionButton(
            label: 'Retry',
            icon: Icons.refresh,
            onPressed: onRetry,
            isPrimary: true,
          ),
        ],
      ),
    );
  }
}

class ResultViewData {
  ResultViewData({
    required this.predictionId,
    required this.engineId,
    required this.cycleId,
    required this.dataTimestep,
    required this.predictedRul,
    required this.status,
    required this.topFeatures,
    required this.featureReadings,
    required this.predictedAt,
    required this.reportText,
  });

  final int? predictionId;
  final int? engineId;
  final int? cycleId;
  final int? dataTimestep;
  final double predictedRul;
  final String status;
  final List<FeatureContribution> topFeatures;
  final Map<String, double> featureReadings;
  final String? predictedAt;
  final String reportText;

  factory ResultViewData.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('prediction') || json.containsKey('report')) {
      final prediction = _asMap(json['prediction']);
      final report = _asMap(json['report']);
      final featuresJson = _asList(
        prediction['top_feature_contributions'] ??
            prediction['all_feature_contributions'] ??
            prediction['top_contributing_features'],
      );

      return ResultViewData(
        predictionId: _asInt(json['prediction_id']),
        engineId: _asInt(prediction['unit'] ?? report['unit'] ?? json['engine_id']),
        cycleId: _asInt(prediction['cycle'] ?? report['cycle'] ?? json['cycle_id']),
        dataTimestep: _asInt(json['data_timestep'] ?? prediction['input_rows']),
        predictedRul: _asDouble(
          prediction['predicted_rul'] ?? report['predicted_rul'] ?? json['predicted_rul'],
        ),
        status: normalizeStatus(report['risk_level'] ?? json['status'] ?? json['health_status']),
        topFeatures: featuresJson.map(FeatureContribution.fromJson).toList(),
        featureReadings: _featureReadingsFromPredictionJson(json),
        predictedAt: json['predicted_at']?.toString(),
        reportText: (report['maintenance_report'] ?? json['report_textfile'] ?? json['maintenance_report'] ?? '').toString(),
      );
    }

    return ResultViewData(
      predictionId: _asInt(json['prediction_id']),
      engineId: _asInt(json['engine_id']),
      cycleId: _asInt(json['cycle_id']),
      dataTimestep: _asInt(json['data_timestep']),
      predictedRul: _asDouble(json['predicted_rul']),
      status: normalizeStatus(json['status'] ?? json['health_status']),
      topFeatures: _asList(json['top_features']).map(FeatureContribution.fromJson).toList(),
      featureReadings: _featureReadingsFromPredictionJson(json),
      predictedAt: json['predicted_at']?.toString(),
      reportText: (json['report_textfile'] ?? json['maintenance_report'] ?? '').toString(),
    );
  }

  ResultViewData withFeatureReadings(Map<String, double> readings) {
    if (readings.isEmpty) return this;

    return ResultViewData(
      predictionId: predictionId,
      engineId: engineId,
      cycleId: cycleId,
      dataTimestep: dataTimestep,
      predictedRul: predictedRul,
      status: status,
      topFeatures: topFeatures,
      featureReadings: <String, double>{
        ...featureReadings,
        ...readings,
      },
      predictedAt: predictedAt,
      reportText: reportText,
    );
  }

  String get predictedRulText {
    if (predictedRul % 1 == 0) return predictedRul.toInt().toString();
    return predictedRul.toStringAsFixed(1);
  }

  String get intervalText {
    if (predictedRul <= 20) return '+/- 3 cycles (CI)';
    if (predictedRul <= 50) return '+/- 6 cycles (CI)';
    if (predictedRul <= 100) return '+/- 8 cycles (CI)';
    return '+/- 15 cycles (CI)';
  }

  String get recommendationText {
    final important = topFeatures.take(3).map((e) => e.displayName).join(', ');
    final focus = important.isEmpty ? 'the highest-risk sensor trends' : important;
    final normalized = normalizeStatus(status);

    if (normalized == 'critical') {
      return 'Prioritize immediate maintenance review. Check $focus and compare the current operating window against recent healthy operation before the next dispatch.';
    }

    if (normalized == 'watch') {
      return 'Advance inspection planning within the next maintenance window. Monitor $focus closely and review whether the same trend continues in the next uploaded cycle.';
    }

    if (normalized == 'ok') {
      return 'Continue routine monitoring. Keep $focus on the next review checklist and compare against fleet baselines during scheduled analysis.';
    }

    return 'Review the prediction output and inspect $focus before making a maintenance decision.';
  }
}

class FeatureContribution {
  FeatureContribution({
    required this.feature,
    required this.shapValue,
    required this.absShapValue,
    required this.importancePercent,
    required this.effect,
    this.rawReading,
  });

  final String feature;
  final double shapValue;
  final double absShapValue;
  final double importancePercent;
  final String effect;
  final double? rawReading;

  factory FeatureContribution.fromJson(Map<String, dynamic> json) {
    return FeatureContribution(
      feature: (json['feature'] ?? json['name'] ?? 'Feature').toString(),
      shapValue: _asDouble(json['shap_value'] ?? json['value'] ?? json['contribution']),
      absShapValue: _asDouble(json['abs_shap_value'] ?? json['abs_value'] ?? json['importance']),
      importancePercent: _asDouble(json['importance_percent'] ?? json['percent']),
      effect: (json['effect'] ?? '').toString(),
      rawReading: _nullableDouble(json['reading'] ?? json['sensor_value'] ?? json['raw_value']),
    );
  }

  String get displayName => _displayFeatureName(feature);

  String get readingText {
    if (rawReading != null) return _formatCompact(rawReading!);
    return 'Not available';
  }

  String get priorityLabel {
    final percent = importancePercent;
    if (percent >= 15) return 'High';
    if (percent >= 8) return 'Medium';
    return 'Low';
  }
}

class SensorTrendData {
  SensorTrendData({
    required this.features,
    required this.series,
  });

  final List<String> features;
  final List<Map<String, double?>> series;
  final Map<String, List<FlSpot>> _normalizedSpotCache = <String, List<FlSpot>>{};

  factory SensorTrendData.fromJson(Map<String, dynamic> json) {
    final features = _asDynamicList(json['decreasing_features']).map((item) => item.toString()).toList();
    final seriesJson = _asDynamicList(json['series']);

    final series = seriesJson.map((item) {
      final map = _asMap(item);
      return map.map((key, value) => MapEntry(key, _nullableDouble(value)));
    }).toList();

    return SensorTrendData(features: features, series: series);
  }

  List<FlSpot> normalizedSpotsFor(String feature) {
    return _normalizedSpotCache.putIfAbsent(feature, () {
      final rawValues = series
          .map((row) => row[feature])
          .whereType<double>()
          .toList();

      if (rawValues.isEmpty) return <FlSpot>[];

      final minValue = rawValues.reduce(math.min);
      final maxValue = rawValues.reduce(math.max);
      final range = maxValue - minValue;

      final spots = <FlSpot>[];
      for (var index = 0; index < series.length; index++) {
        final rawValue = series[index][feature];
        if (rawValue == null) continue;
        final normalized = range == 0 ? 0.5 : (rawValue - minValue) / range;
        spots.add(FlSpot(index.toDouble(), normalized.clamp(0.0, 1.0)));
      }
      return spots;
    });
  }

  double rawValueAt(String feature, int index) {
    if (index < 0 || index >= series.length) return 0;
    return series[index][feature] ?? 0;
  }

  String cycleLabelFor(int index) {
    if (series.isEmpty) return '';
    final safeIndex = index.clamp(0, series.length - 1).toInt();
    final timestep = series[safeIndex]['timestep'];
    if (timestep == null) {
      return 'T${safeIndex + 1}';
    }
    final timestepNumber = timestep.round();
    return 'T$timestepNumber';
  }
}

class FleetHealthCounts {
  FleetHealthCounts({
    required this.ok,
    required this.watch,
    required this.critical,
  });

  final int ok;
  final int watch;
  final int critical;

  int get total => ok + watch + critical;

  String get signature => '$ok/$watch/$critical';

  factory FleetHealthCounts.fromJson(Map<String, dynamic> json) {
    final fleetHealth = _asMap(json['fleet_health']);
    return FleetHealthCounts(
      ok: _asInt(fleetHealth['ok']) ?? 0,
      watch: _asInt(fleetHealth['watch']) ?? 0,
      critical: _asInt(fleetHealth['critical']) ?? 0,
    );
  }
}

class HealthProbabilities {
  HealthProbabilities({
    required this.normal,
    required this.watch,
    required this.critical,
  });

  final double normal;
  final double watch;
  final double critical;

  factory HealthProbabilities.fromStatus(String status) {
    switch (normalizeStatus(status)) {
      case 'ok':
        return HealthProbabilities(normal: 86, watch: 10, critical: 4);
      case 'watch':
        return HealthProbabilities(normal: 65, watch: 25, critical: 10);
      case 'critical':
        return HealthProbabilities(normal: 10, watch: 30, critical: 60);
      default:
        return HealthProbabilities(normal: 34, watch: 33, critical: 33);
    }
  }
}

class ReportSection {
  ReportSection({required this.title, required this.body});

  final String title;
  final String body;
}

class _ReportSections {
  _ReportSections(this.items);

  final List<ReportSection> items;

  factory _ReportSections.fromResult(ResultViewData result) {
    final text = result.reportText.trim();
    final knownHeadings = <String>[
      'Executive Summary',
      'Engine Performance Analysis',
      'Critical Findings',
      'Risk Classification Assessment',
      'Review Focus',
      'Recommendations and Action Items',
      'Conclusion',
    ];

    if (text.isNotEmpty) {
      final parsed = _parseKnownHeadingSections(text, knownHeadings);
      if (parsed.isNotEmpty) return _ReportSections(parsed);
    }

    final featureSentence = result.topFeatures.isEmpty
        ? 'No detailed feature contribution values were returned with this result.'
        : 'The largest model associations are ${result.topFeatures.take(5).map((f) => '${f.displayName} (${f.priorityLabel.toLowerCase()} priority, ${f.importancePercent.toStringAsFixed(2)}%)').join(', ')}.';

    return _ReportSections([
      ReportSection(
        title: 'Executive Summary',
        body: 'The predictive analysis conducted on Engine ${result.engineId ?? '-'} indicates a ${_titleCase(normalizeStatus(result.status))} status with a predicted Remaining Useful Life (RUL) of ${result.predictedRulText} cycles. The assessment is based on the uploaded sensor window, the latest saved prediction, and the model feature-contribution output.',
      ),
      ReportSection(
        title: 'Engine Performance Analysis',
        body: text.isEmpty ? 'No generated maintenance paragraph was returned by the report service for this prediction.' : text,
      ),
      ReportSection(
        title: 'Critical Findings',
        body: featureSentence,
      ),
      ReportSection(
        title: 'Recommendations and Action Items',
        body: result.recommendationText,
      ),
    ]);
  }

  static List<ReportSection> _parseKnownHeadingSections(String text, List<String> headings) {
    final normalized = text.replaceAll('\r\n', '\n').trim();
    final lines = normalized.split('\n');
    final sections = <ReportSection>[];
    String? currentTitle;
    final currentBody = <String>[];

    String cleanHeadingCandidate(String value) {
      return value
          .trim()
          .replaceAll(RegExp(r'^#+\s*'), '')
          .replaceAll(RegExp(r'^\*\*'), '')
          .replaceAll(RegExp(r'\*\*$'), '')
          .replaceAll(RegExp(r'^__'), '')
          .replaceAll(RegExp(r'__$'), '')
          .replaceAll(RegExp(r':$'), '')
          .trim();
    }

    String cleanBodyLine(String value) {
      return value
          .replaceAll(RegExp(r'^\s*\*\*'), '')
          .replaceAll(RegExp(r'\*\*\s*$'), '')
          .trimRight();
    }

    String? matchedHeading(String value) {
      final cleaned = cleanHeadingCandidate(value);
      for (final heading in headings) {
        if (cleaned.toLowerCase() == heading.toLowerCase()) {
          return heading;
        }
      }
      return null;
    }

    void flush() {
      final title = currentTitle;
      if (title == null) return;

      final body = currentBody
          .map(cleanBodyLine)
          .where((line) => line.trim().isNotEmpty)
          .join('\n')
          .trim();
      if (body.isNotEmpty) {
        sections.add(ReportSection(title: title, body: body));
      }
      currentBody.clear();
    }

    for (final rawLine in lines) {
      final heading = matchedHeading(rawLine);
      if (heading != null) {
        flush();
        currentTitle = heading;
      } else if (currentTitle != null) {
        currentBody.add(rawLine);
      }
    }

    flush();
    return sections;
  }
}

class AppPalette {
  static const Color pageBackground = Color(0xFFF6F7F9);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color softCard = Color(0xFFF8F9FB);
  static const Color tabBackground = Color(0xFFEDEFF4);
  static const Color border = Color(0xFFDDE2E8);
  static const Color primaryBlack = Color(0xFF030014);
  static const Color textPrimary = Color(0xFF020617);
  static const Color textMuted = Color(0xFF667085);
  static const Color axisText = Color(0xFF475467);
  static const Color axisBorder = Color(0xFF9CA3AF);
  static const Color chartGrid = Color(0xFFD7DCE4);
  static const Color blue = Color(0xFF2563EB);
  static const Color green = Color(0xFF22C55E);
  static const Color amber = Color(0xFFF2B705);
  static const Color red = Color(0xFFEF4444);
  static const Color purple = Color(0xFF7C3AED);
  static const Color teal = Color(0xFF14B8A6);
}

class AppText {
  static TextStyle get _base => GoogleFonts.inter();

  static TextStyle get smallLabel => _base.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppPalette.textPrimary,
      );

  static TextStyle get rulValue => _base.copyWith(
        fontSize: 20,
        height: 1.05,
        fontWeight: FontWeight.w500,
        color: AppPalette.textPrimary,
      );

  static TextStyle get caption => _base.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
      );

  static TextStyle get badge => _base.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w800,
      );

  static TextStyle get button => _base.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w800,
      );

  static TextStyle get tab => _base.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get body => _base.copyWith(
        fontSize: 12,
        height: 1.35,
      );

  static TextStyle get sectionTitle => _base.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppPalette.textPrimary,
      );

  static TextStyle get reportHeading => _base.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: AppPalette.textPrimary,
      );

  static TextStyle get reportBody => _base.copyWith(
        fontSize: 13,
        height: 1.72,
        fontWeight: FontWeight.w500,
        color: Color(0xFF172554),
      );

  static TextStyle get chip => _base.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppPalette.textPrimary,
      );

  static TextStyle get axis => _base.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppPalette.axisText,
      );
}

String normalizeStatus(Object? status) {
  final value = (status ?? '').toString().trim().toLowerCase();
  if (value == 'ok' || value == 'normal' || value == 'low') return 'ok';
  if (value == 'watch' || value == 'warning' || value == 'medium') return 'watch';
  if (value == 'critical' || value == 'high') return 'critical';
  if (value.isEmpty) return 'unknown';
  return value;
}

Color _statusColor(String status) {
  switch (normalizeStatus(status)) {
    case 'ok':
      return AppPalette.green;
    case 'watch':
      return AppPalette.amber;
    case 'critical':
      return AppPalette.red;
    default:
      return AppPalette.textMuted;
  }
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1).toLowerCase();
}


Map<String, double> _featureReadingsFromPredictionJson(Map<String, dynamic> json) {
  final readings = <String, double>{};
  final prediction = _asMap(json['prediction']);

  void collectSummary(Object? value) {
    final summary = _asMap(value);
    for (final entry in summary.entries) {
      final feature = entry.key;
      final stats = _asMap(entry.value);
      final reading = _nullableDouble(
        stats['latest'] ??
            stats['last'] ??
            stats['value'] ??
            stats['mean'] ??
            stats['max'] ??
            stats['min'],
      );
      if (reading != null) {
        readings[feature] = reading;
        readings[_displayFeatureName(feature)] = reading;
      }
    }
  }

  collectSummary(prediction['sensor_summary']);
  collectSummary(prediction['operating_condition_summary']);
  collectSummary(json['sensor_summary']);
  collectSummary(json['operating_condition_summary']);

  return readings;
}

Map<String, double> _latestValuesFromSensorGroups(Map<String, dynamic> json) {
  final readings = <String, double>{};
  final seriesByGroup = _asMap(json['series']);

  for (final groupEntry in seriesByGroup.entries) {
    final groupMap = _asMap(groupEntry.value);
    for (final featureEntry in groupMap.entries) {
      final feature = featureEntry.key;
      final values = _asDynamicList(featureEntry.value);

      for (final value in values.reversed) {
        final reading = _nullableDouble(value);
        if (reading != null) {
          readings[feature] = reading;
          readings[_displayFeatureName(feature)] = reading;
          break;
        }
      }
    }
  }

  return readings;
}

String _displayFeatureName(String feature) {
  const names = <String, String>{
    'alt': 'Altitude',
    'Mach': 'Mach',
    'TRA': 'TRA',
    'T2': 'T2',
    'T24': 'T24',
    'T30': 'T30',
    'T48': 'T48',
    'T50': 'T50',
    'P15': 'P15',
    'P2': 'P2',
    'P21': 'P21',
    'P24': 'P24',
    'Ps30': 'Ps30',
    'P40': 'P40',
    'P50': 'P50',
    'Nf': 'Nf',
    'Nc': 'Nc',
    'Wf': 'Wf',
    'EGT': 'EGT',
    'Vibration R': 'Vibration R',
    'Oil Pressure': 'Oil Pressure',
    'Fuel Flow': 'Fuel Flow',
  };
  return names[feature] ?? feature.replaceAll('_', ' ');
}

String _formatCompact(num value) {
  final number = value.toDouble();
  final absValue = number.abs();
  if (absValue >= 1000) return number.toStringAsFixed(0);
  if (absValue >= 100) return number.toStringAsFixed(0);
  if (absValue >= 10) return number.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  return number.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}

String _formatAxisTick(double value) {
  if (value == 0) return '0';
  if (value.abs() >= 1) return value.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return value.toStringAsFixed(2);
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, dynamic item) => MapEntry(key.toString(), item));
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _asList(Object? value) {
  if (value is List) {
    return value
        .whereType<Object>()
        .map((item) => _asMap(item))
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return <Map<String, dynamic>>[];
}

List<dynamic> _asDynamicList(Object? value) {
  if (value is List) return value;
  return <dynamic>[];
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double _asDouble(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

double? _nullableDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

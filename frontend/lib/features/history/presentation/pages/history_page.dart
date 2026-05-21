import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:predection_desktop_app/shared/layouts/main_layout.dart';


enum _ReportSaveFormat {
  pdf('PDF document', 'pdf'),
  word('Word document', 'doc'),
  text('Text file', 'txt');

  const _ReportSaveFormat(this.label, this.extension);

  final String label;
  final String extension;
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const MainLayout(currentRoute: '/history', child: _HistoryContent());
  }
}

class _HistoryContent extends StatefulWidget {
  const _HistoryContent();

  @override
  State<_HistoryContent> createState() => _HistoryContentState();
}

class _HistoryContentState extends State<_HistoryContent> {
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

  final TextEditingController _engineController = TextEditingController();
  final TextEditingController _cycleController = TextEditingController();

  List<_HistoryRow> _rows = [];
  String _statusFilter = 'all';
  OverlayEntry? _toastEntry;
  final Set<int> _exportingIds = <int>{};

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _engineController.dispose();
    _cycleController.dispose();
    _toastEntry?.remove();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _dio.get('/history');
      final data = response.data;

      if (data is Map && data['error'] != null) {
        throw Exception(data['error']);
      }

      if (data is! List) {
        throw Exception('Invalid history response.');
      }

      final rows = <_HistoryRow>[];

      for (final item in data) {
        if (item is! Map) {
          continue;
        }

        rows.add(_HistoryRow.fromMap(Map<String, dynamic>.from(item)));
      }

      rows.sort((a, b) {
        final aTime = DateTime.tryParse(a.time);
        final bTime = DateTime.tryParse(b.time);

        if (aTime == null || bTime == null) {
          return b.predictionId.compareTo(a.predictionId);
        }

        return bTime.compareTo(aTime);
      });

      setState(() {
        _rows = rows;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load prediction history: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<_HistoryRow> get _filteredRows {
    final engineQuery = _engineController.text.trim().toLowerCase();
    final cycleQuery = _cycleController.text.trim().toLowerCase();

    return _rows.where((row) {
      if (_statusFilter != 'all' && row.status != _statusFilter) {
        return false;
      }

      if (engineQuery.isNotEmpty) {
        final engineValue = row.engineId.toString().toLowerCase();
        final engineLabel = 'eng-${row.engineId}'.toLowerCase();
        final paddedEngineLabel = 'eng-${row.engineId.toString().padLeft(4, '0')}'.toLowerCase();

        if (engineQuery != engineValue &&
            engineQuery != engineLabel &&
            engineQuery != paddedEngineLabel) {
          return false;
        }
      }

      if (cycleQuery.isNotEmpty && cycleQuery != row.cycleId.toString().toLowerCase()) {
        return false;
      }

      return true;
    }).toList();
  }

  void _applyFilters() {
    setState(() {});
  }

  void _resetFilters() {
    _engineController.clear();
    _cycleController.clear();
    setState(() {
      _statusFilter = 'all';
    });
  }

  void _openResult(_HistoryRow row) {
    if (row.predictionId <= 0) {
      _showToast(
        'Cannot open result',
        message: 'This history row is missing a valid prediction id.',
        isError: true,
      );
      return;
    }

    Navigator.of(context, rootNavigator: true).pushNamed(
      '/results',
      arguments: {'prediction_id': row.predictionId, 'source': 'history'},
    );
  }

  Future<void> _exportReport(_HistoryRow row) async {
    if (row.predictionId <= 0 || _exportingIds.contains(row.predictionId)) {
      return;
    }

    final format = await _chooseReportFormat();
    if (format == null) {
      return;
    }

    setState(() {
      _exportingIds.add(row.predictionId);
    });

    try {
      final response = await _dio.get('/results/${row.predictionId}');
      final data = response.data;

      if (data is! Map) {
        throw Exception('Invalid result response.');
      }

      final map = Map<String, dynamic>.from(data);

      if (map['error'] != null) {
        throw Exception(map['error']);
      }

      final report = _HistoryReportData.fromResultMap(map, fallback: row);
      final defaultName = _defaultReportFileName(report, format);

      final selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save prediction report as ${format.label}',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: [format.extension],
      );

      if (selectedPath == null) {
        return;
      }

      final outputPath = _ensureExtension(selectedPath, format.extension);
      final sections = _ReportSections.fromReportText(report.reportText);

      await _writeReportFile(
        outputPath: outputPath,
        format: format,
        report: report,
        sections: sections,
      );

      _showToast(
        'Report saved',
        message: 'The ${format.extension.toUpperCase()} report was saved successfully.',
      );
    } catch (e) {
      _showToast(
        'Save failed',
        message: e.toString(),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _exportingIds.remove(row.predictionId);
        });
      }
    }
  }

  Future<_ReportSaveFormat?> _chooseReportFormat() {
    return showDialog<_ReportSaveFormat>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text(
            'Save report as',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'Choose the format you want to download for this prediction report.',
            style: TextStyle(color: Color(0xFF64748B)),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
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
                elevation: 0,
                backgroundColor: const Color(0xFF020617),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _defaultReportFileName(
    _HistoryReportData report,
    _ReportSaveFormat format,
  ) {
    return 'engine_health_report_engine_${report.engineId}_cycle_${report.cycleId}_prediction_${report.predictionId}.${format.extension}';
  }

  String _ensureExtension(String selectedPath, String extension) {
    final requiredExtension = '.$extension';
    if (selectedPath.toLowerCase().endsWith(requiredExtension)) {
      return selectedPath;
    }
    return '$selectedPath$requiredExtension';
  }

  Future<void> _writeReportFile({
    required String outputPath,
    required _ReportSaveFormat format,
    required _HistoryReportData report,
    required _ReportSections sections,
  }) async {
    switch (format) {
      case _ReportSaveFormat.pdf:
        final bytes = await _buildPdfReport(report, sections);
        await File(outputPath).writeAsBytes(bytes, flush: true);
        return;
      case _ReportSaveFormat.word:
        await File(outputPath).writeAsString(
          _buildWordCompatibleReport(report, sections),
          encoding: utf8,
          flush: true,
        );
        return;
      case _ReportSaveFormat.text:
        await File(outputPath).writeAsString(
          _buildPlainTextReport(report, sections),
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

  Future<List<int>> _buildPdfReport(
    _HistoryReportData report,
    _ReportSections sections,
  ) async {
    final pdf = pw.Document();
    final metaRows = _reportMetadataRows(report);

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


  String _buildWordCompatibleReport(
    _HistoryReportData report,
    _ReportSections sections,
  ) {
    final rowsHtml = _reportMetadataRows(report).map((row) {
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

  String _buildPlainTextReport(
    _HistoryReportData report,
    _ReportSections sections,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('Engine Health Analysis Report');
    buffer.writeln();

    for (final row in _reportMetadataRows(report)) {
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

  List<MapEntry<String, String>> _reportMetadataRows(_HistoryReportData report) {
    return [
      MapEntry('Prediction ID', report.predictionId.toString()),
      MapEntry('Engine ID', report.engineId.toString()),
      MapEntry('Cycle ID', report.cycleId.toString()),
      MapEntry('Data Timestep', report.dataTimestep?.toString() ?? '-'),
      MapEntry('Predicted RUL', '${report.predictedRulText} cycles'),
      MapEntry('Status', report.statusLabel),
      MapEntry('Prediction Time', report.predictedAt),
    ];
  }

  String _escapeHtml(String value) {
    return const HtmlEscape(HtmlEscapeMode.element).convert(value);
  }

  void _showToast(String title, {String? message, bool isError = false}) {
    if (!mounted) {
      return;
    }

    _toastEntry?.remove();
    _toastEntry = null;

    final overlay =
        Overlay.maybeOf(context, rootOverlay: true) ?? Overlay.maybeOf(context);

    if (overlay == null) {
      return;
    }

    final accentColor = isError ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
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
                            style: const TextStyle(
                              color: Color(0xFF111827),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (message != null && message.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        entry.remove();
                        if (identical(_toastEntry, entry)) {
                          _toastEntry = null;
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Color(0xFF64748B),
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
      if (!mounted) {
        return;
      }
      if (identical(_toastEntry, entry)) {
        entry.remove();
        _toastEntry = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredRows = _filteredRows;

    return RefreshIndicator(
      onRefresh: _loadHistory,
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
            _buildFilterCard(),
            const SizedBox(height: 24),
            _buildHistoryTable(filteredRows),
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
                'Prediction History',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Browse, filter, reopen, and export saved prediction reports',
                style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _loadHistory,
          tooltip: 'Refresh history',
          icon: const Icon(Icons.refresh_rounded, color: Color(0xFF2563EB)),
        ),
      ],
    );
  }

  Widget _buildFilterCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 900;

              final fields = [
                _TextFilterField(
                  label: 'Engine ID',
                  controller: _engineController,
                  hintText: 'Search engine...',
                  icon: Icons.search_rounded,
                  onSubmitted: (_) => _applyFilters(),
                ),
                _TextFilterField(
                  label: 'Cycle ID',
                  controller: _cycleController,
                  hintText: 'Search cycle...',
                  icon: Icons.confirmation_number_outlined,
                  onSubmitted: (_) => _applyFilters(),
                ),
                _StatusDropdown(
                  value: _statusFilter,
                  onChanged: (value) {
                    setState(() {
                      _statusFilter = value ?? 'all';
                    });
                  },
                ),
              ];

              if (compact) {
                return Column(
                  children: [
                    for (final field in fields) ...[
                      field,
                      const SizedBox(height: 16),
                    ],
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 16),
                  Expanded(child: fields[1]),
                  const SizedBox(width: 16),
                  Expanded(child: fields[2]),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _applyFilters,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF020617),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.filter_alt_outlined, size: 18),
                label: const Text(
                  'Apply Filters',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _resetFilters,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF111827),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(
                  'Reset',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTable(List<_HistoryRow> rows) {
    return Container(
      width: double.infinity,
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Saved Predictions',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                Text(
                  '${rows.length} shown',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(34),
              child: Center(
                child: Text(
                  'No prediction history rows match the current filters.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                // Keep the table responsive. It should fill the card on normal
                // desktop widths, and only become horizontally scrollable on
                // very small windows.
                final tableWidth = constraints.maxWidth < 1040
                    ? 1040.0
                    : constraints.maxWidth;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Column(
                      children: [
                        const _HistoryHeaderRow(),
                        for (final row in rows)
                          _HistoryDataRow(
                            row: row,
                            isExporting: _exportingIds.contains(row.predictionId),
                            onView: () => _openResult(row),
                            onExport: () => _exportReport(row),
                          ),
                      ],
                    ),
                  ),
                );
              },
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
}

class _TextFilterField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final ValueChanged<String> onSubmitted;

  const _TextFilterField({
    required this.label,
    required this.controller,
    required this.hintText,
    required this.icon,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 9),
        TextField(
          controller: controller,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: Icon(icon, color: const Color(0xFF94A3B8)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 15,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2563EB)),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String?> onChanged;

  const _StatusDropdown({required this.value, required this.onChanged});

  static const _items = [
    DropdownMenuItem(value: 'all', child: Text('All statuses')),
    DropdownMenuItem(value: 'ok', child: Text('Ok')),
    DropdownMenuItem(value: 'watch', child: Text('Watch')),
    DropdownMenuItem(value: 'critical', child: Text('Critical')),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Status',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 9),
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              borderRadius: BorderRadius.circular(12),
              dropdownColor: Colors.white,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF111827),
              ),
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF64748B),
              ),
              items: _items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryHeaderRow extends StatelessWidget {
  const _HistoryHeaderRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(
          top: BorderSide(color: Color(0xFFE5E7EB)),
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: const Row(
        children: [
          SizedBox(width: 118, child: _HeaderText('Run ID')),
          SizedBox(width: 165, child: _HeaderText('Time')),
          SizedBox(width: 130, child: _HeaderText('Engine')),
          SizedBox(width: 88, child: _HeaderText('Cycle')),
          SizedBox(width: 118, child: _HeaderText('RUL')),
          SizedBox(width: 118, child: _HeaderText('Status')),
          Expanded(child: _HeaderText('Notes')),
          SizedBox(
            width: 112,
            child: Align(
              alignment: Alignment.centerRight,
              child: _HeaderText('Actions'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryDataRow extends StatelessWidget {
  final _HistoryRow row;
  final bool isExporting;
  final VoidCallback onView;
  final VoidCallback onExport;

  const _HistoryDataRow({
    required this.row,
    required this.isExporting,
    required this.onView,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 118,
            child: Text(
              row.runId,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: 165,
            child: Text(
              row.formattedTime,
              style: const TextStyle(color: Color(0xFF334155)),
            ),
          ),
          SizedBox(
            width: 130,
            child: Text(
              'ENG-${row.engineId}',
              style: const TextStyle(color: Color(0xFF111827)),
            ),
          ),
          SizedBox(
            width: 88,
            child: Text(
              row.cycleId.toString(),
              style: const TextStyle(color: Color(0xFF111827)),
            ),
          ),
          SizedBox(
            width: 118,
            child: Text(
              row.formattedRul,
              style: const TextStyle(color: Color(0xFF111827)),
            ),
          ),
          SizedBox(
            width: 118,
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: row.statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  row.statusLabel,
                  style: const TextStyle(color: Color(0xFF334155)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              row.notes,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF334155)),
            ),
          ),
          SizedBox(
            width: 112,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TableActionButton(
                  icon: Icons.visibility_outlined,
                  semanticLabel: 'View prediction',
                  onPressed: onView,
                ),
                const SizedBox(width: 8),
                _TableActionButton(
                  icon: Icons.download_rounded,
                  semanticLabel: isExporting ? 'Saving report' : 'Download report',
                  onPressed: isExporting ? null : onExport,
                  isLoading: isExporting,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _TableActionButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool isLoading;

  const _TableActionButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: SizedBox(
        width: 42,
        height: 34,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF111827),
            disabledForegroundColor: const Color(0xFF64748B),
            side: const BorderSide(color: Color(0xFFE5E7EB)),
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, size: 17),
        ),
      ),
    );
  }
}

class _HeaderText extends StatelessWidget {
  final String text;

  const _HeaderText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF111827),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _AnimatedToast extends StatefulWidget {
  final String title;
  final String? message;
  final bool isError;
  final VoidCallback onDone;

  const _AnimatedToast({
    required this.title,
    required this.message,
    required this.isError,
    required this.onDone,
  });

  @override
  State<_AnimatedToast> createState() => _AnimatedToastState();
}

class _AnimatedToastState extends State<_AnimatedToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    _controller.forward();
    _closeLater();
  }

  Future<void> _closeLater() async {
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) {
      return;
    }

    await _controller.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isError
        ? const Color(0xFFDC2626)
        : const Color(0xFF16A34A);
    final background = widget.isError
        ? const Color(0xFFFEF2F2)
        : const Color(0xFFF0FDF4);
    final border = widget.isError
        ? const Color(0xFFFECACA)
        : const Color(0xFFBBF7D0);

    return Positioned(
      left: 280,
      right: 32,
      bottom: 28,
      child: IgnorePointer(
        child: SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Material(
              color: Colors.transparent,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: background,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            widget.isError
                                ? Icons.error_outline_rounded
                                : Icons.check_circle_outline_rounded,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF111827),
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                ),
                              ),
                              if (widget.message != null && widget.message!.trim().isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  widget.message!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
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
          ),
        ),
      ),
    );
  }
}


class _HistoryReportData {
  final int predictionId;
  final int engineId;
  final int cycleId;
  final int? dataTimestep;
  final double predictedRul;
  final String status;
  final String predictedAt;
  final String reportText;

  const _HistoryReportData({
    required this.predictionId,
    required this.engineId,
    required this.cycleId,
    required this.dataTimestep,
    required this.predictedRul,
    required this.status,
    required this.predictedAt,
    required this.reportText,
  });

  factory _HistoryReportData.fromResultMap(
    Map<String, dynamic> map, {
    required _HistoryRow fallback,
  }) {
    final reportTextValue = map['report_textfile']?.toString().trim() ?? '';

    return _HistoryReportData(
      predictionId:
          int.tryParse(map['prediction_id']?.toString() ?? '') ?? fallback.predictionId,
      engineId: int.tryParse(map['engine_id']?.toString() ?? '') ?? fallback.engineId,
      cycleId: int.tryParse(map['cycle_id']?.toString() ?? '') ?? fallback.cycleId,
      dataTimestep:
          int.tryParse(map['data_timestep']?.toString() ?? '') ?? fallback.dataTimestep,
      predictedRul:
          double.tryParse(map['predicted_rul']?.toString() ?? '') ?? fallback.predictedRul,
      status: _normalizeStatus(map['status'] ?? fallback.status),
      predictedAt: map['predicted_at']?.toString() ?? fallback.time,
      reportText: reportTextValue.isNotEmpty
          ? reportTextValue
          : 'No report text is available for this prediction.',
    );
  }

  String get predictedRulText {
    if (predictedRul % 1 == 0) {
      return predictedRul.toInt().toString();
    }

    return predictedRul.toStringAsFixed(1);
  }

  String get statusLabel {
    switch (status) {
      case 'ok':
        return 'Ok';
      case 'watch':
        return 'Watch';
      case 'critical':
        return 'Critical';
      default:
        return status.isEmpty ? 'Unknown' : status;
    }
  }
}

class _ReportSection {
  final String title;
  final String body;

  const _ReportSection({required this.title, required this.body});
}

class _ReportSections {
  static const List<String> knownHeadings = [
    'Executive Summary',
    'Engine Performance Analysis',
    'Critical Findings',
    'Risk Classification Assessment',
    'Review Focus',
    'Recommendations and Action Items',
    'Conclusion',
  ];

  final List<_ReportSection> items;

  const _ReportSections(this.items);

  factory _ReportSections.fromReportText(String text) {
    final parsed = _parseKnownHeadingSections(text, knownHeadings);
    if (parsed.isNotEmpty) {
      return _ReportSections(parsed);
    }

    final cleaned = text.trim();
    return _ReportSections([
      _ReportSection(
        title: 'Maintenance Report',
        body: cleaned.isEmpty ? 'No report text is available.' : cleaned,
      ),
    ]);
  }

  static List<_ReportSection> _parseKnownHeadingSections(
    String text,
    List<String> headings,
  ) {
    final normalized = text.replaceAll('\r\n', '\n').trim();
    final lines = normalized.split('\n');
    final sections = <_ReportSection>[];
    String? currentTitle;
    final currentBody = <String>[];

    void flush() {
      final title = currentTitle;
      if (title == null) return;

      final body = currentBody.join('\n').trim();
      if (body.isNotEmpty) {
        sections.add(_ReportSection(title: title, body: body));
      }
      currentBody.clear();
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (headings.contains(line)) {
        flush();
        currentTitle = line;
      } else if (currentTitle != null) {
        currentBody.add(rawLine);
      }
    }

    flush();
    return sections;
  }
}

class _HistoryRow {
  final String runId;
  final int predictionId;
  final int engineId;
  final int cycleId;
  final int? dataTimestep;
  final double predictedRul;
  final String status;
  final String time;

  const _HistoryRow({
    required this.runId,
    required this.predictionId,
    required this.engineId,
    required this.cycleId,
    required this.dataTimestep,
    required this.predictedRul,
    required this.status,
    required this.time,
  });

  factory _HistoryRow.fromMap(Map<String, dynamic> map) {
    final predictionId =
        int.tryParse(map['prediction_id']?.toString() ?? '') ??
        int.tryParse(map['id']?.toString() ?? '') ??
        0;

    return _HistoryRow(
      runId:
          map['run_id']?.toString() ??
          'RUN-${predictionId.toString().padLeft(3, '0')}',
      predictionId: predictionId,
      engineId: int.tryParse(map['engine_id']?.toString() ?? '') ?? 0,
      cycleId: int.tryParse(map['cycle_id']?.toString() ?? '') ?? 0,
      dataTimestep: int.tryParse(map['data_timestep']?.toString() ?? ''),
      predictedRul:
          double.tryParse(map['predicted_rul']?.toString() ?? '') ?? 0,
      status: _normalizeStatus(map['status']),
      time: map['time']?.toString() ?? map['predicted_at']?.toString() ?? '',
    );
  }

  String get formattedRul {
    if (predictedRul % 1 == 0) {
      return predictedRul.toInt().toString();
    }

    return predictedRul.toStringAsFixed(1);
  }

  String get formattedTime {
    final parsed = DateTime.tryParse(time);

    if (parsed == null) {
      return time.isEmpty ? 'N/A' : time;
    }

    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} '
        '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  String get statusLabel {
    switch (status) {
      case 'ok':
        return 'Ok';
      case 'watch':
        return 'Watch';
      case 'critical':
        return 'Critical';
      default:
        return status.isEmpty ? 'Unknown' : status;
    }
  }

  Color get statusColor {
    switch (status) {
      case 'ok':
        return const Color(0xFF22C55E);
      case 'watch':
        return const Color(0xFFEAB308);
      case 'critical':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF64748B);
    }
  }

  String get notes {
    switch (status) {
      case 'critical':
        return 'Requires maintenance review';
      case 'watch':
        return 'Monitor trend closely';
      case 'ok':
        return 'All nominal';
      default:
        return 'Review prediction result';
    }
  }
}

String _normalizeStatus(dynamic value) {
  final status = value?.toString().toLowerCase().trim() ?? '';

  if (status == 'ok' || status == 'normal' || status == 'low') {
    return 'ok';
  }

  if (status == 'watch' || status == 'warning' || status == 'medium') {
    return 'watch';
  }

  if (status == 'critical' || status == 'high') {
    return 'critical';
  }

  return status.isEmpty ? 'unknown' : status;
}

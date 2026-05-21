import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:predection_desktop_app/shared/layouts/main_layout.dart';

import 'prediction_auto_navigation_patch.dart';

class PredictionsPage extends StatelessWidget {
  const PredictionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const MainLayout(
      currentRoute: '/predictions',
      child: _PredictionsContent(),
    );
  }
}

class _PredictionsContent extends StatefulWidget {
  const _PredictionsContent();

  @override
  State<_PredictionsContent> createState() => _PredictionsContentState();
}

class _PredictionsContentState extends State<_PredictionsContent> {

  File? _selectedFile;
  String? _selectedFileName;
  String? _errorMessage;
  String? _successMessage;
  bool _isRunning = false;

  Future<void> _pickCsvFile() async {
    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      allowMultiple: false,
      withData: false,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final path = result.files.single.path;

    if (path == null || path.isEmpty) {
      setState(() {
        _errorMessage = 'Could not read the selected file path.';
      });
      return;
    }

    final file = File(path);

    if (!await file.exists()) {
      setState(() {
        _errorMessage = 'Selected file does not exist.';
      });
      return;
    }

    setState(() {
      _selectedFile = file;
      _selectedFileName = result.files.single.name;
    });
  }

  Future<void> _runPrediction() async {
    if (_selectedFile == null) {
      setState(() {
        _errorMessage = 'Please select a CSV file first.';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isRunning = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await uploadCsvThenOpenResults(
        context: context,
        csvPath: _selectedFile!.path,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _successMessage = 'Prediction completed successfully.';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Prediction failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildUploadCard(),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                _buildMessageBox(
                  message: _errorMessage!,
                  color: const Color(0xFFDC2626),
                  backgroundColor: const Color(0xFFFEF2F2),
                  borderColor: const Color(0xFFFECACA),
                  icon: Icons.error_outline,
                ),
              ],
              if (_successMessage != null) ...[
                const SizedBox(height: 16),
                _buildMessageBox(
                  message: _successMessage!,
                  color: const Color(0xFF16A34A),
                  backgroundColor: const Color(0xFFF0FDF4),
                  borderColor: const Color(0xFFBBF7D0),
                  icon: Icons.check_circle_outline,
                ),
              ],
              const SizedBox(height: 24),
              _buildRunButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Run Prediction',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Upload a CSV file to run the RUL prediction model and generate the maintenance report.',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Data Source',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 22),
          InkWell(
            onTap: _isRunning ? null : _pickCsvFile,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 42,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _selectedFile == null
                      ? const Color(0xFFCBD5E1)
                      : const Color(0xFF2563EB),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    _selectedFile == null
                        ? Icons.upload_file_outlined
                        : Icons.description_outlined,
                    size: 48,
                    color: _selectedFile == null
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF2563EB),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _selectedFileName == null
                        ? 'Drop CSV file here or click to browse'
                        : _selectedFileName!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _selectedFile == null
                          ? const Color(0xFF111827)
                          : const Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Required columns: unit/engine_id, cycle/cycle_id, alt, Mach, TRA, T2, T24, T30, T48, T50, P15, P2, P21, P24, Ps30, P40, P50, Nf, Nc, Wf',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _isRunning ? null : _pickCsvFile,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF111827),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: Text(
                      _selectedFile == null ? 'Select File' : 'Change File',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRunButton() {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _isRunning ? null : _runPrediction,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF020617),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF94A3B8),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        icon: _isRunning
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.play_arrow_rounded, size: 20),
        label: Text(
          _isRunning ? 'Running Prediction...' : 'Run Prediction',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBox({
    required String message,
    required Color color,
    required Color backgroundColor,
    required Color borderColor,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
              ),
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
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Interactive RUL health indicator used in the Analytics fleet table.
///
/// Color rules:
/// - RUL <= 20      -> Critical / red
/// - 20 < RUL <= 40 -> Watch / amber
/// - RUL > 40       -> OK / green
///
/// The filled width is based on the RUL value compared with [maxRulForFullBar].
/// Pass the maximum RUL from the currently displayed table if you want the bars
/// to compare rows against each other.
class RulHealthIndicatorBar extends StatefulWidget {
  const RulHealthIndicatorBar({
    super.key,
    required this.rul,
    this.maxRulForFullBar = 100,
    this.width = 260,
    this.height = 8,
    this.showTextValue = false,
  });

  final num rul;
  final num maxRulForFullBar;
  final double width;
  final double height;
  final bool showTextValue;

  @override
  State<RulHealthIndicatorBar> createState() => _RulHealthIndicatorBarState();
}

class _RulHealthIndicatorBarState extends State<RulHealthIndicatorBar> {
  bool _hovered = false;

  double get _rulValue => widget.rul.toDouble();

  double get _maxValue {
    final value = widget.maxRulForFullBar.toDouble();
    if (value <= 0) return 1;
    return value;
  }

  double get _percent {
    final raw = _rulValue / _maxValue;
    if (raw.isNaN || raw.isInfinite) return 0;
    return raw.clamp(0.0, 1.0);
  }

  String get _status {
    if (_rulValue <= 20) return 'Critical';
    if (_rulValue <= 40) return 'Watch';
    return 'OK';
  }

  String get _rangeText {
    if (_rulValue <= 20) return 'Critical range: 20 cycles or below';
    if (_rulValue <= 40) return 'Watch range: above 20 to 40 cycles';
    return 'OK range: above 40 cycles';
  }

  Color get _barColor {
    if (_rulValue <= 20) return const Color(0xFFEF4444);
    if (_rulValue <= 40) return const Color(0xFFF2B705);
    return const Color(0xFF22C55E);
  }

  @override
  Widget build(BuildContext context) {
    final percentText = '${(_percent * 100).toStringAsFixed(1)}%';
    final rulText = _rulValue == _rulValue.roundToDouble()
        ? _rulValue.toInt().toString()
        : _rulValue.toStringAsFixed(1);

    return Tooltip(
      waitDuration: const Duration(milliseconds: 250),
      message: 'RUL: $rulText cycles\nStatus: $_status\nBar: $percentText\n$_rangeText',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          scale: _hovered ? 1.015 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: widget.width,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Stack(
                    children: [
                      Container(
                        height: widget.height,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5E7EB),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        height: widget.height,
                        width: math.max(widget.height, widget.width * _percent),
                        decoration: BoxDecoration(
                          color: _barColor,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: _hovered
                              ? [
                                  BoxShadow(
                                    color: _barColor.withOpacity(0.28),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.showTextValue) ...[
                const SizedBox(width: 10),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  style: TextStyle(
                    color: _hovered ? _barColor : const Color(0xFF667085),
                    fontWeight: _hovered ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 12,
                  ),
                  child: Text('$rulText cycles • $percentText'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

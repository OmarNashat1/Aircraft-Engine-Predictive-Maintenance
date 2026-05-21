import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:predection_desktop_app/features/dashboard/domain/entities/alert_entity.dart';

class RecentAlertsList extends StatelessWidget {
  final List<AlertEntity> alerts;

  const RecentAlertsList({super.key, required this.alerts});

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Alerts',
                style: TextStyle(
                  color: Color(0xFFE6EDF3),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton(
                onPressed: () {},
                child: const Text(
                  'View All',
                  style: TextStyle(color: Color(0xFF1E6FD9), fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (alerts.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No recent alerts',
                  style: TextStyle(color: Color(0xFF8B949E), fontSize: 14),
                ),
              ),
            )
          else
            ...alerts.take(5).map((alert) => _buildAlertItem(alert)),
        ],
      ),
    );
  }

  Widget _buildAlertItem(AlertEntity alert) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    Color severityColor;
    IconData severityIcon;

    switch (alert.alertLevel.toLowerCase()) {
      case 'critical':
        severityColor = const Color(0xFFDA3633);
        severityIcon = Icons.error;
        break;
      case 'watch':
      case 'acknowledged':
        severityColor = const Color(0xFFD29922);
        severityIcon = Icons.warning;
        break;
      default:
        severityColor = const Color(0xFF8B949E);
        severityIcon = Icons.info;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        children: [
          // Severity Icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: severityColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(severityIcon, color: severityColor, size: 18),
          ),
          const SizedBox(width: 12),

          // Alert Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      alert.engineId,
                      style: const TextStyle(
                        color: Color(0xFFE6EDF3),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: severityColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        alert.alertLevel.toUpperCase(),
                        style: TextStyle(
                          color: severityColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  alert.message,
                  style: const TextStyle(
                    color: Color(0xFF8B949E),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dateFormat.format(alert.createdAt),
                  style: const TextStyle(
                    color: Color(0xFF8B949E),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // Actions
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.visibility_outlined),
                color: const Color(0xFF8B949E),
                iconSize: 20,
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.close),
                color: const Color(0xFF8B949E),
                iconSize: 20,
                onPressed: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

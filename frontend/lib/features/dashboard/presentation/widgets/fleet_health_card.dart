import 'package:flutter/material.dart';
import 'package:predection_desktop_app/features/dashboard/domain/entities/fleet_health_entity.dart';

class FleetHealthCard extends StatelessWidget {
  final FleetHealthEntity fleetHealth;

  const FleetHealthCard({super.key, required this.fleetHealth});

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
            'Fleet Health',
            style: TextStyle(
              color: Color(0xFFE6EDF3),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStatusItem(
                count: fleetHealth.okCount,
                label: 'OK',
                color: const Color(0xFF2EA043),
              ),
              const SizedBox(width: 8),
              const Text(
                '/',
                style: TextStyle(
                  color: Color(0xFF8B949E),
                  fontSize: 32,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(width: 8),
              _buildStatusItem(
                count: fleetHealth.watchCount,
                label: 'WATCH',
                color: const Color(0xFFD29922),
              ),
              const SizedBox(width: 8),
              const Text(
                '/',
                style: TextStyle(
                  color: Color(0xFF8B949E),
                  fontSize: 32,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(width: 8),
              _buildStatusItem(
                count: fleetHealth.criticalCount,
                label: 'CRITICAL',
                color: const Color(0xFFDA3633),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'OK / WATCH / CRITICAL',
              style: TextStyle(color: const Color(0xFF8B949E), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem({
    required int count,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              count.toString(),
              style: TextStyle(
                color: const Color(0xFFE6EDF3),
                fontSize: 32,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

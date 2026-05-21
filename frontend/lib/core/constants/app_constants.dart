/// Application constants for Aircraft Engine Prediction Desktop App
class AppConstants {
  // Navigation routes
  static const String loginRoute = '/login';
  static const String dashboardRoute = '/dashboard';
  static const String engineHealthRoute = '/engine-health';
  static const String alertsRoute = '/alerts';

  // Desktop window configuration
  static const double minWindowWidth = 1200.0;
  static const double minWindowHeight = 800.0;

  // Animation durations
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 300);
  static const Duration longAnimation = Duration(milliseconds: 500);

  // Spacing values (desktop-optimized)
  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 16.0;
  static const double spacingL = 24.0;
  static const double spacingXL = 32.0;
  static const double spacingXXL = 48.0;

  // Navigation rail width
  static const double navigationRailWidth = 80.0;
  static const double navigationRailWidthExtended = 200.0;

  // Card dimensions
  static const double cardBorderRadius = 12.0;
  static const double cardElevation = 2.0;

  // Chart dimensions
  static const double chartHeight = 300.0;
  static const double chartHeightLarge = 400.0;

  // Engine status values
  static const String statusHealthy = 'Healthy';
  static const String statusWarning = 'Warning';
  static const String statusCritical = 'Critical';

  // Alert severity levels
  static const String severityLow = 'Low';
  static const String severityMedium = 'Medium';
  static const String severityHigh = 'High';
  static const String severityCritical = 'Critical';
}

/// API endpoint constants
/// Update BASE_URL with your actual backend URL
class ApiConstants {
  // Base URL - CHANGE THIS TO YOUR BACKEND URL
  static const String baseUrl = 'http://127.0.0.1:8000';

  // Timeouts
  static const int connectTimeout = 10000; // 10 seconds
  static const int receiveTimeout = 60000; // 60 seconds
  static const int sendTimeout = 30000; // 30 seconds

  // Auth endpoints
  static const String login = '/login';
  static const String logout = '/logout';

  // Dashboard endpoints
  static const String dashboardSummary = '/dashboard-summary';
  static const String fleetHealth = '/dashboard/fleet-health';
  static const String recentAlerts = '/dashboard/alerts/recent';
  static const String fleetTrend = '/dashboard/trend';

  // Prediction endpoints
  static const String uploadCsv = '/upload-csv';
  static const String runPrediction = '/predictions/run';
  static const String getPredictionResult = '/predictions';
  static const String savePrediction = '/predictions';
  static const String exportPdf = '/export/pdf';

  // History endpoints
  static const String history = '/history';

  // Alerts endpoints
  static const String alerts = '/alerts';
  static const String resolveAlert = '/alerts';
}

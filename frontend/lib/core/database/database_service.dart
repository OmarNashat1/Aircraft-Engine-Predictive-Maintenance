import 'package:injectable/injectable.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Local database service for storing prediction history
@lazySingleton
class DatabaseService {
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'engine_predictions.db');

    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE prediction_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        prediction_id TEXT NOT NULL,
        engine_id TEXT NOT NULL,
        unit INTEGER NOT NULL,
        cycle INTEGER NOT NULL,
        predicted_rul INTEGER NOT NULL,
        risk_level TEXT NOT NULL,
        status TEXT NOT NULL,
        notes TEXT,
        timestamp TEXT NOT NULL
      )
    ''');
  }

  /// Save prediction to history
  Future<int> savePrediction({
    required String predictionId,
    required String engineId,
    required int unit,
    required int cycle,
    required int predictedRul,
    required String riskLevel,
    required String status,
    String? notes,
  }) async {
    final db = await database;
    return await db.insert('prediction_history', {
      'prediction_id': predictionId,
      'engine_id': engineId,
      'unit': unit,
      'cycle': cycle,
      'predicted_rul': predictedRul,
      'risk_level': riskLevel,
      'status': status,
      'notes': notes,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Get all predictions
  Future<List<Map<String, dynamic>>> getAllPredictions() async {
    final db = await database;
    return await db.query('prediction_history', orderBy: 'timestamp DESC');
  }

  /// Get predictions with filters
  Future<List<Map<String, dynamic>>> getFilteredPredictions({
    String? engineId,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await database;
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (engineId != null && engineId.isNotEmpty) {
      whereClause += 'engine_id LIKE ?';
      whereArgs.add('%$engineId%');
    }

    if (status != null && status.isNotEmpty && status != 'All statuses') {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'status = ?';
      whereArgs.add(status);
    }

    if (startDate != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'timestamp >= ?';
      whereArgs.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'timestamp <= ?';
      whereArgs.add(endDate.toIso8601String());
    }

    return await db.query(
      'prediction_history',
      where: whereClause.isEmpty ? null : whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'timestamp DESC',
    );
  }

  /// Delete prediction
  Future<int> deletePrediction(String predictionId) async {
    final db = await database;
    return await db.delete(
      'prediction_history',
      where: 'prediction_id = ?',
      whereArgs: [predictionId],
    );
  }

  /// Clear all history
  Future<int> clearHistory() async {
    final db = await database;
    return await db.delete('prediction_history');
  }
}

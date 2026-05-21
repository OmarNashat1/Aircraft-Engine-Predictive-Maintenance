import 'dart:async';
import 'dart:convert';
import 'dart:io';

class BackendProcessService {
  BackendProcessService._();

  static final BackendProcessService instance = BackendProcessService._();

  Process? _process;
  bool _startedByThisApp = false;
  bool _backendExited = false;

  static const String backendHost = '127.0.0.1';
  static const int backendPort = 8000;
  static const int modelApiPort = 9000;

  String get baseUrl => 'http://$backendHost:$backendPort';

  Future<void> start() async {
    if (await isHealthy()) {
      _startedByThisApp = false;
      return;
    }

    final appRoot = await _resolveAppRoot();

    final backendDir = Directory('${appRoot.path}\\backend');
    final backendExe = File('${backendDir.path}\\backend.exe');

    final modelApiDir = Directory('${appRoot.path}\\model_api');
    final modelApiExe = File('${modelApiDir.path}\\model_api.exe');

    final reportsDir = Directory('${appRoot.path}\\reports');
    final logsDir = Directory('${backendDir.path}\\logs');

    if (!await backendExe.exists()) {
      throw Exception('backend.exe was not found at: ${backendExe.path}');
    }

    if (!await modelApiDir.exists()) {
      throw Exception('model_api folder was not found at: ${modelApiDir.path}');
    }

    if (!await modelApiExe.exists()) {
      throw Exception('model_api.exe was not found at: ${modelApiExe.path}');
    }
    await reportsDir.create(recursive: true);
    await logsDir.create(recursive: true);

    final environment = Map<String, String>.from(Platform.environment);

    environment['BACKEND_HOST'] = backendHost;
    environment['BACKEND_PORT'] = backendPort.toString();

    environment['MODEL_API_AUTOSTART'] = 'true';
    environment['MODEL_API_DIR'] = modelApiDir.path;
    environment['MODEL_API_MAIN'] = 'model_api.exe';
    environment['MODEL_API_PYTHON'] = modelApiExe.path;
    environment['MODEL_API_STARTUP_TIMEOUT'] = '60';

    environment['ML_SERVER_URL'] =
        'http://127.0.0.1:$modelApiPort/predict/rul/report';

    environment['REPORTS_FOLDER'] = reportsDir.path;

    final modelFolder = Directory('${modelApiDir.path}\\Model');
    if (await modelFolder.exists()) {
      environment['ARTIFACT_DIR'] = modelFolder.path;
    } else {
      environment['ARTIFACT_DIR'] = modelApiDir.path;
    }

    _backendExited = false;

    _process = await Process.start(
      backendExe.path,
      const [],
      workingDirectory: backendDir.path,
      runInShell: false,
      mode: ProcessStartMode.normal,
      environment: environment,
    );

    _startedByThisApp = true;

    _process!.exitCode.then((code) {
      _backendExited = true;
      stderr.writeln('[backend-exit] backend.exe exited with code $code');
    });

    _process!.stdout
        .transform(utf8.decoder)
        .listen((line) => stdout.write('[backend] $line'));

    _process!.stderr
        .transform(utf8.decoder)
        .listen((line) => stderr.write('[backend-error] $line'));

    await _waitUntilHealthy();
  }

  Future<void> stop() async {
    if (_process == null || !_startedByThisApp) {
      return;
    }

    final backendPid = _process!.pid;

    if (Platform.isWindows) {
      await Process.run('taskkill', [
        '/PID',
        backendPid.toString(),
        '/T',
        '/F',
      ], runInShell: true);

      await _killProcessListeningOnPort(backendPort);
      await _killProcessListeningOnPort(modelApiPort);
    } else {
      _process!.kill(ProcessSignal.sigterm);
    }

    _process = null;
    _startedByThisApp = false;
    _backendExited = false;
  }

  Future<bool> isHealthy() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);

    try {
      final request = await client
          .getUrl(Uri.parse('$baseUrl/'))
          .timeout(const Duration(seconds: 2));

      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );

      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }

      try {
        final data = jsonDecode(body);
        return data is Map && data['message'] == 'Backend API is working';
      } catch (_) {
        return body.contains('Backend API is working');
      }
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _waitUntilHealthy() async {
    const maxAttempts = 90;

    for (int i = 0; i < maxAttempts; i++) {
      if (await isHealthy()) {
        return;
      }

      if (_backendExited) {
        throw Exception(
          'backend.exe exited before becoming ready. '
          'Check backend/logs/backend_stdout.log and backend/logs/backend_stderr.log.',
        );
      }

      await Future.delayed(const Duration(seconds: 1));
    }

    await stop();

    throw Exception(
      'Backend did not start after $maxAttempts seconds. '
      'Check backend/backend.exe, backend/.env, model_api/model_api.exe, model_api/Model, and port $backendPort.',
    );
  }

  Future<Directory> _resolveAppRoot() async {
    final candidates = <Directory>[];

    final appRootOverride = Platform.environment['APP_ROOT'];
    if (appRootOverride != null && appRootOverride.trim().isNotEmpty) {
      candidates.add(Directory(appRootOverride.trim()));
    }

    candidates.add(File(Platform.resolvedExecutable).parent);
    candidates.add(Directory.current);
    candidates.add(Directory.current.parent);

    final checked = <String>{};

    for (final candidate in candidates) {
      final normalized = candidate.path;

      if (checked.contains(normalized)) {
        continue;
      }

      checked.add(normalized);

      final backendExe = File('${candidate.path}\\backend\\backend.exe');
      final modelApiDir = Directory('${candidate.path}\\model_api');
      final modelApiExe = File('${candidate.path}\\model_api\\model_api.exe');

      if (await backendExe.exists() &&
          await modelApiDir.exists() &&
          await modelApiExe.exists()) {
        return candidate;
      }
    }

    throw Exception(
      'Could not resolve app root. Checked:\n${checked.join('\n')}\n\n'
      'Expected structure:\n'
      'Expected structure:\n'
      'app/backend/backend.exe\n'
      'app/model_api/model_api.exe\n'
      'app/model_api/_internal/\n'
      'app/model_api/Model/',
    );
  }

  Future<void> _killProcessListeningOnPort(int port) async {
    if (!Platform.isWindows) {
      return;
    }

    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '''
\$connections = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if (\$connections) {
  \$connections | ForEach-Object {
    taskkill /PID \$_.OwningProcess /T /F | Out-Null
  }
}
''',
      ], runInShell: true);

      if (result.exitCode != 0) {
        stderr.write(result.stderr);
      }
    } catch (_) {
      // Ignore cleanup fallback errors.
    }
  }
}

import 'dart:io';
import 'package:path_provider/path_provider.dart';

class AppMonitoring {
  static final AppMonitoring _instance = AppMonitoring._internal();
  factory AppMonitoring() => _instance;
  AppMonitoring._internal();

  // Метрики
  int _totalDetections = 0;
  int _confirmedDetections = 0;
  int _falsePositives = 0;
  int _crashes = 0;
  int _sessionCount = 0;
  
  DateTime? _sessionStart;
  List<Map<String, dynamic>> _detectionLog = [];
  List<Map<String, dynamic>> _errorLog = [];

  // Геттеры
  int get totalDetections => _totalDetections;
  int get confirmedDetections => _confirmedDetections;
  int get falsePositives => _falsePositives;
  int get crashes => _crashes;
  double get accuracyRate => _totalDetections > 0 
      ? (_confirmedDetections / _totalDetections) * 100 
      : 0;
  double get falsePositiveRate => _totalDetections > 0 
      ? (_falsePositives / _totalDetections) * 100 
      : 0;

  // Инициализация сессии
  void startSession() {
    _sessionStart = DateTime.now();
    _sessionCount++;
    _logEvent('SESSION_START', {'session_id': _sessionCount});
  }

  void endSession() {
    if (_sessionStart != null) {
      final duration = DateTime.now().difference(_sessionStart!);
      _logEvent('SESSION_END', {
        'session_id': _sessionCount,
        'duration_seconds': duration.inSeconds,
      });
    }
  }

  // Логирование детекции
  void logDetection(bool isDogBark, Map<String, dynamic> metadata) {
    _totalDetections++;
    if (isDogBark) {
      _confirmedDetections++;
    }
    
    _detectionLog.add({
      'timestamp': DateTime.now().toIso8601String(),
      'is_dog_bark': isDogBark,
      'metadata': metadata,
    });

    _saveMetrics();
  }

  // Логирование удаления (ложное срабатывание)
  void logFalsePositive() {
    _confirmedDetections--;
    _falsePositives++;
    
    _logEvent('FALSE_POSITIVE_REMOVED', {
      'confirmed': _confirmedDetections,
      'false_positives': _falsePositives,
    });

    _saveMetrics();
  }

  // Логирование ошибок
  void logError(String error, String stackTrace) {
    _errorLog.add({
      'timestamp': DateTime.now().toIso8601String(),
      'error': error,
      'stack_trace': stackTrace,
    });

    _crashes++;
    _saveMetrics();
  }

  // Сброс статистики
  void resetMetrics() {
    _totalDetections = 0;
    _confirmedDetections = 0;
    _falsePositives = 0;
    _detectionLog.clear();
    _saveMetrics();
  }

  // Получение отчёта
  Map<String, dynamic> getReport() {
    return {
      'session_count': _sessionCount,
      'total_detections': _totalDetections,
      'confirmed_detections': _confirmedDetections,
      'false_positives': _falsePositives,
      'accuracy_rate': accuracyRate.toStringAsFixed(1),
      'false_positive_rate': falsePositiveRate.toStringAsFixed(1),
      'crashes': _crashes,
      'session_start': _sessionStart?.toIso8601String(),
    };
  }

  // Внутренние методы
  void _logEvent(String event, Map<String, dynamic> data) {
    print('MONITORING [$event]: $data');
  }

  Future<void> _saveMetrics() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/monitoring_metrics.txt');
      
      final report = getReport();
      final content = '''
Monitoring Report
Generated: ${DateTime.now()}

Sessions: ${report['session_count']}
Total Detections: ${report['total_detections']}
Confirmed: ${report['confirmed_detections']}
False Positives: ${report['false_positives']}
Accuracy: ${report['accuracy_rate']}%
False Positive Rate: ${report['false_positive_rate']}%
Crashes: ${report['crashes']}

Last 10 Detections:
${_detectionLog.take(10).map((e) => '- ${e['timestamp']}: ${e['is_dog_bark']} ${e['metadata']}').join('\n')}
''';
      
      await file.writeAsString(content);
    } catch (e) {
      print('Error saving metrics: $e');
    }
  }
}

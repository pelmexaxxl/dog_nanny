import 'package:flutter/material.dart';
import 'package:mic_stream/mic_stream.dart';
import 'package:permission_handler/permission_handler.dart';
import 'audio_classifier.dart';
import 'dart:async';
import 'dart:math';
import 'monitoring.dart';

void main() => runApp(DogNannyApp());

class DogNannyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dog Nanny ML',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MonitorScreen(),
    );
  }
}

class MonitorScreen extends StatefulWidget {
  @override
  _MonitorScreenState createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  final AudioClassifier _classifier = AudioClassifier();
  final AppMonitoring _monitoring = AppMonitoring();

  StreamSubscription<List<int>>? _micStream;
  bool _isRecording = false;
  String _status = "Готов к мониторингу";
  int _barkCount = 0;
  
  DetectionMode _mode = DetectionMode.economical;
  
  List<int> _audioBuffer = [];
  DateTime? _lastBarkTime;
  List<Map<String, dynamic>> _history = []; // Хранит объекты
  int _falsePositives = 0; // Счётчик удалённых
  
  String _freqInfo = "";
  double _currentDb = 0.0;
  double _threshold = 70.0;

  @override
  void initState() {
    super.initState();
    _initClassifier();
    _monitoring.startSession();
  }

  Future<void> _initClassifier() async {
    await _classifier.initialize();
    _classifier.setMode(_mode);
  }

  void _switchMode(DetectionMode mode) {
    setState(() {
      _mode = mode;
      _classifier.setMode(mode);
    });
  }

  void _toggleRecording() async {
    if (_isRecording) {
      await _micStream?.cancel();
      setState(() {
        _isRecording = false;
        _status = "Остановлено. Всего лаев: $_barkCount";
      });
    } else {
      var status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        setState(() => _status = "Нет доступа к микрофону");
        return;
      }
      
      try {
        Stream<List<int>> stream = await MicStream.microphone(
          sampleRate: 16000,
          channelConfig: ChannelConfig.CHANNEL_IN_MONO,
          audioFormat: AudioFormat.ENCODING_PCM_16BIT,
        );
        
        _micStream = stream.listen((bytes) {
          // print('Получено байт: ${bytes.length}');
          
          // КОНВЕРТИРУЕМ БАЙТЫ В INT16 PCM
          List<int> samples = [];
          for (int i = 0; i < bytes.length - 1; i += 2) {
            // Little-endian Int16
            int sample = (bytes[i] & 0xFF) | ((bytes[i + 1] & 0xFF) << 8);
            
            // Преобразуем в signed
            if (sample > 32767) {
              sample = sample - 65536;
            }
            
            samples.add(sample);
          }
          
          // ДИАГНОСТИКА
          // if (samples.length >= 10) {
          //   print('Первые 10 PCM сэмплов: ${samples.sublist(0, 10)}');
          //   int maxSample = samples.reduce((a, b) => a.abs() > b.abs() ? a : b);
          //   print('Максимальный PCM: $maxSample');
          // }
          
          _audioBuffer.addAll(samples);
          
          // Каждые 0.5 сек анализируем
          if (_audioBuffer.length >= 8000) {
            _analyzeAudio();
            _audioBuffer = _audioBuffer.sublist(_audioBuffer.length - 8000);
          }
        });
                        
        setState(() {
          _isRecording = true;
          _barkCount = 0;
          _falsePositives = 0; // ДОБАВЬ
          _history.clear();
          _audioBuffer.clear();
          _status = "Слушаю...";
        });

      } catch (e) {
        print('Ошибка: $e');
        _monitoring.logError(e.toString(), StackTrace.current.toString());
        setState(() => _status = "Ошибка: $e");
      }
    }
  }

  Future<void> _analyzeAudio() async {
    if (_audioBuffer.length < 512) {
      print('Буфер слишком мал: ${_audioBuffer.length}');
      return;
    }
    
    // print('Анализируем ${_audioBuffer.length} сэмплов');
    
    // ВЫЧИСЛЯЕМ ГРОМКОСТЬ (средняя амплитуда)
    double sum = 0;
    for (int sample in _audioBuffer) {
      sum += sample.abs();
    }
    double avgAmplitude = sum / _audioBuffer.length;

    // Логарифмическая шкала (как настоящие dB)
    // Амплитуда 100 = 40 dБ, 1000 = 60 dB, 10000 = 80 dB
    double db = avgAmplitude > 0 ? 20 * log(avgAmplitude) / ln10 : 0;

    print('Средняя амплитуда: $avgAmplitude, dB: $db');

    setState(() {
      _currentDb = db.clamp(0, 100);
    });

    // ПРОВЕРКА ПОРОГА
    if (_currentDb < _threshold) {
      // print('Слишком тихо: ${_currentDb.toInt()} < $_threshold');
      return;
    }
        
    final now = DateTime.now();
    if (_lastBarkTime != null && now.difference(_lastBarkTime!).inSeconds < 2) {
      // print('Антидребезг');
      return;
    }
    
    var result = await _classifier.classify(_audioBuffer);
    
    print('Результат классификации: $result');

    // ДИАГНОСТИКА: всегда показываем данные
    setState(() {
      _freqInfo = "Freq: ${result['dominantFreq']} Hz, E: ${result['energy']}";
      if (result.containsKey('spectralCentroid')) {
        _freqInfo += ", C: ${result['spectralCentroid']} Hz";
      }
      if (result.containsKey('freqRatio')) {
        _freqInfo += ", R: ${result['freqRatio']}";
      }
      if (result.containsKey('dogScore')) {
        _freqInfo += ", Dog: ${result['dogScore']}, Bark: ${result['barkScore']}";
      }
    });
        
    if (result['isDogBark'] == true) {
      _lastBarkTime = now;
      _barkCount++;
      
      _monitoring.logDetection(true, {
        'method': result['method'],
        'confidence': result['confidence'],
        'dominant_freq': result['dominantFreq'],
      });

      setState(() {
        _status = "ЛАЙ ОБНАРУЖЕН!";
        _freqInfo = "Частота: ${result['dominantFreq']} Гц, Энергия: ${result['energy']}";
        if (result.containsKey('mlScore')) {
          _freqInfo += ", ML: ${result['mlScore']}";
        }
      });
      
      String method = result['method'];
      _addToHistory("Лай #$_barkCount - $method");
      
      Future.delayed(Duration(seconds: 2), () {
        if (_isRecording) {
          setState(() => _status = "Слушаю...");
        }
      });
    }
  }

  void _addToHistory(String event) {
    setState(() {
      var time = DateTime.now();
      _history.insert(0, {
        'time': "${time.hour}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}",
        'event': event,
        'id': DateTime.now().millisecondsSinceEpoch, // Уникальный ID
      });
      if (_history.length > 20) _history.removeLast(); // Увеличил лимит
    });
  }

  void _removeFromHistory(int index) {
    setState(() {
      _history.removeAt(index);
      _barkCount--; // Уменьшаем счётчик
      _falsePositives++; // Увеличиваем ложные
      _monitoring.logFalsePositive();
    });
  }

  @override
  void dispose() {
    _micStream?.cancel();
    _classifier.dispose();
    _monitoring.endSession();
    super.dispose();
  }

  void _showMonitoringReport() {
    final report = _monitoring.getReport();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.analytics, color: Colors.purple),
            SizedBox(width: 8),
            Text('Отчёт мониторинга'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildReportRow('Сессий', '${report['session_count']}'),
              Divider(),
              _buildReportRow('Всего детекций', '${report['total_detections']}'),
              _buildReportRow('Подтверждённых', '${report['confirmed_detections']}'),
              _buildReportRow('Ложных', '${report['false_positives']}'),
              Divider(),
              _buildReportRow('Точность', '${report['accuracy_rate']}%'),
              _buildReportRow('FP Rate', '${report['false_positive_rate']}%'),
              Divider(),
              _buildReportRow('Crashes', '${report['crashes']}'),
              SizedBox(height: 10),
              Text(
                'Метрики сохранены локально',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _monitoring.resetMetrics();
              Navigator.pop(context);
              setState(() {
                _barkCount = 0;
                _falsePositives = 0;
                _history.clear();
              });
            },
            child: Text('Сбросить'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14)),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dog Nanny ML'),
        backgroundColor: Colors.blue[700],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              SizedBox(height: 10),
              
              // РЕЖИМЫ ДЕТЕКЦИИ
              Container(
                padding: EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.purple[50],
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.purple, width: 2),
                ),
                child: Column(
                  children: [
                    Text('Режим детекции', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildModeButton('Частоты', DetectionMode.economical, Colors.green),
                        SizedBox(width: 10),
                        _buildModeButton('ML+Частоты', DetectionMode.precise, Colors.purple),
                      ],
                    ),
                    SizedBox(height: 10),
                    Text(
                      _mode == DetectionMode.economical
                          ? 'FFT анализ частот'
                          : 'YAMNet ML + FFT',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 20),
              
              // ИНДИКАТОР ГРОМКОСТИ
              if (_isRecording)
                Container(
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey[400]!, width: 2),
                  ),
                  child: Column(
                    children: [
                      Text('Громкость:', style: TextStyle(fontSize: 14)),
                      SizedBox(height: 5),
                      Text(
                        '${_currentDb.toInt()} дБ',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: _currentDb > _threshold ? Colors.red : Colors.green,
                        ),
                      ),
                      SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: (_currentDb / 100).clamp(0.0, 1.0),
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _currentDb > _threshold ? Colors.red : Colors.green,
                        ),
                        minHeight: 8,
                      ),
                    ],
                  ),
                ),
              
              SizedBox(height: 20),
              
              // ИКОНКА МИКРОФОНА
              Icon(
                _isRecording ? Icons.mic : Icons.mic_off,
                size: 100,
                color: _isRecording ? Colors.red : Colors.grey,
              ),
              
              SizedBox(height: 20),
              
              // СТАТУС
              Container(
                padding: EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: _status.contains("ЛАЙ") ? Colors.red[100] : Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      _status,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _status.contains("ЛАЙ") ? Colors.red[900] : Colors.blue[900],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_freqInfo.isNotEmpty) // && _status.contains("ЛАЙ"))
                      Padding(
                        padding: EdgeInsets.only(top: 5),
                        child: Text(
                          _freqInfo,
                          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        ),
                      ),
                  ],
                ),
              ),
              
              SizedBox(height: 15),
              
              // СЧЕТЧИК ЛАЕВ
              Container(
                padding: EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green, width: 2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.pets, color: Colors.green[700], size: 30),
                    SizedBox(width: 10),
                    Column(
                      children: [
                        Text('Лаев обнаружено', style: TextStyle(fontSize: 14, color: Colors.green[900])),
                        Text('$_barkCount', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.green[700])),
                      ],
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 20),
              
              // ПОЛЗУНОК ПОРОГА
              Container(
                padding: EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text('Порог срабатывания', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    Text('${_threshold.toInt()} дБ', style: TextStyle(fontSize: 20, color: Colors.orange[900])),
                    Slider(
                      value: _threshold,
                      min: 50,
                      max: 85,
                      divisions: 7,
                      label: '${_threshold.toInt()} дБ',
                      activeColor: Colors.orange,
                      onChanged: (value) => setState(() => _threshold = value),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 20),
              
              // КНОПКА
              ElevatedButton(
                onPressed: _toggleRecording,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  child: Text(
                    _isRecording ? 'Остановить' : 'Начать мониторинг',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRecording ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
              
              SizedBox(height: 20),
              
              // ИСТОРИЯ
              if (_history.isNotEmpty)
                Container(
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('История лаев:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      ..._history.asMap().entries.map((entry) {
                        int index = entry.key;
                        var item = entry.value;
                        return Container(
                          margin: EdgeInsets.only(bottom: 5),
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${item['time']} - ${item['event']}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(),
                                onPressed: () => _removeFromHistory(index),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              SizedBox(height: 20),

              // СТАТИСТИКА
              Container(
                padding: EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue[200]!, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.analytics, color: Colors.blue[700], size: 20),
                        SizedBox(width: 8),
                        Text('Статистика', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue[900])),
                      ],
                    ),
                    SizedBox(height: 10),
                    _buildStatRow('Подтверждённых лаев:', '$_barkCount', Colors.green),
                    _buildStatRow('Ложных (удалено):', '$_falsePositives', Colors.red),
                    if (_barkCount + _falsePositives > 0)
                      _buildStatRow(
                        'Точность:',
                        '${((_barkCount / (_barkCount + _falsePositives)) * 100).toStringAsFixed(1)}%',
                        Colors.blue,
                      ),
                  ],
                ),
              ),

              SizedBox(height: 15),

              // КНОПКА ОТЧЁТА МОНИТОРИНГА
              ElevatedButton.icon(
                onPressed: _showMonitoringReport,
                icon: Icon(Icons.analytics_outlined),
                label: Text('Отчёт мониторинга'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple[600],
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeButton(String label, DetectionMode mode, Color color) {
    bool isSelected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchMode(mode),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color, width: 2),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : color,
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildStatRow(String label, String value, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'audio_classifier.dart';

void main() => runApp(DogNannyApp());

class DogNannyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dog Nanny',
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
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final AudioClassifier _classifier = AudioClassifier();
  
  bool _isRecording = false;
  String _status = "Готов к мониторингу";
  int _barkCount = 0;
  double _threshold = 65.0; // Порог в дБ
  double _currentDb = 0.0;
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _initRecorder();
    _initClassifier();
  }

  Future<void> _initRecorder() async {
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      setState(() {
        _status = "⚠️ Нет доступа к микрофону";
      });
      return;
    }
    await _recorder.openRecorder();
    print('✅ Recorder готов');
  }

  Future<void> _initClassifier() async {
    await _classifier.initialize();
  }

  void _toggleRecording() async {
    if (_isRecording) {
      await _recorder.stopRecorder();
      setState(() {
        _isRecording = false;
        _status = "Остановлено. Всего лаев: $_barkCount";
      });
    } else {
      try {
        await _recorder.startRecorder(
          toFile: 'temp_audio.aac',
          codec: Codec.aacADTS,
          numChannels: 1,
          sampleRate: 16000,
        );
        
        // Обновление каждые 300мс
        _recorder.setSubscriptionDuration(Duration(milliseconds: 300));
        
        // Слушаем поток аудио
        _recorder.onProgress!.listen((event) {
          double decibels = event.decibels ?? 0;
          
          setState(() {
            _currentDb = decibels;
            
            // Проверка порога
            if (decibels > _threshold) {
              _barkCount++;
              _status = "🐕 ЛАЙ ОБНАРУЖЕН!";
              _addToHistory("Лай #$_barkCount - ${decibels.toInt()} дБ");
              
              // Возвращаем обычный статус через 2 секунды
              Future.delayed(Duration(seconds: 2), () {
                if (_isRecording) {
                  setState(() {
                    _status = "🎧 Слушаю...";
                  });
                }
              });
            } else if (_isRecording && _status.contains("Слушаю")) {
              _status = "🎧 Слушаю... ${decibels.toInt()} дБ";
            }
          });
        });
        
        setState(() {
          _isRecording = true;
          _barkCount = 0;
          _history.clear();
          _status = "🎧 Слушаю...";
        });
      } catch (e) {
        print('❌ Ошибка запуска: $e');
        setState(() {
          _status = "Ошибка: $e";
        });
      }
    }
  }

  void _addToHistory(String event) {
    setState(() {
      _history.insert(0, "${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second} - $event");
      if (_history.length > 10) {
        _history.removeLast();
      }
    });
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    _classifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dog Nanny 🐕'),
        backgroundColor: Colors.blue[700],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              SizedBox(height: 20),
              
              // Иконка микрофона
              Icon(
                _isRecording ? Icons.mic : Icons.mic_off,
                size: 100,
                color: _isRecording ? Colors.red : Colors.grey,
              ),
              
              SizedBox(height: 30),
              
              // Статус
              Container(
                padding: EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: _status.contains("ЛАЙ") ? Colors.red[100] : Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _status,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _status.contains("ЛАЙ") ? Colors.red[900] : Colors.blue[900],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              
              SizedBox(height: 20),
              
              // Текущая громкость
              if (_isRecording)
                Container(
                  padding: EdgeInsets.all(10),
                  child: Column(
                    children: [
                      Text('Громкость:', style: TextStyle(fontSize: 16)),
                      SizedBox(height: 5),
                      Text(
                        '${_currentDb.toInt()} дБ',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: _currentDb > _threshold ? Colors.red : Colors.green,
                        ),
                      ),
                      LinearProgressIndicator(
                        value: (_currentDb / 100).clamp(0.0, 1.0),
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _currentDb > _threshold ? Colors.red : Colors.green,
                        ),
                        minHeight: 10,
                      ),
                    ],
                  ),
                ),
              
              SizedBox(height: 20),
              
              // Счетчик лаев
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green, width: 2),
                ),
                child: Column(
                  children: [
                    Text(
                      'Лаев обнаружено',
                      style: TextStyle(fontSize: 16, color: Colors.green[900]),
                    ),
                    SizedBox(height: 5),
                    Text(
                      '$_barkCount',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 30),
              
              // Слайдер чувствительности
              Container(
                padding: EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      'Чувствительность (порог)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 5),
                    Text(
                      '${_threshold.toInt()} дБ',
                      style: TextStyle(fontSize: 24, color: Colors.orange[900]),
                    ),
                    Slider(
                      value: _threshold,
                      min: 40,
                      max: 90,
                      divisions: 10,
                      label: '${_threshold.toInt()} дБ',
                      activeColor: Colors.orange,
                      onChanged: (value) {
                        setState(() => _threshold = value);
                      },
                    ),
                    Text(
                      'Ниже = чувствительнее',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 30),
              
              // Кнопка старт/стоп
              ElevatedButton(
                onPressed: _toggleRecording,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  child: Text(
                    _isRecording ? '🛑 Остановить' : '▶️ Начать мониторинг',
                    style: TextStyle(fontSize: 20),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRecording ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
              
              SizedBox(height: 30),
              
              // История событий
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
                      Text(
                        'История событий:',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 10),
                      ..._history.map((event) => Padding(
                        padding: EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          event,
                          style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                        ),
                      )).toList(),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

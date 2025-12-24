import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class AudioClassifier {
  Interpreter? _interpreter;
  bool _isInitialized = false;

  // Инициализация модели
  Future<void> initialize() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/yamnet.tflite');
      _isInitialized = true;
      print('YAMNet модель загружена');
    } catch (e) {
      print('Ошибка загрузки модели: $e');
    }
  }

  // Анализ аудио
  Future<Map<String, dynamic>> classifyAudio(List<double> audioData) async {
    if (!_isInitialized || _interpreter == null) {
      return {'isDogBark': false, 'confidence': 0.0, 'error': 'Модель не загружена'};
    }

    try {
      // Подготовка входных данных (YAMNet ожидает 15600 сэмплов)
      var input = _prepareInput(audioData);
      
      // Выходной тензор (521 класс YAMNet)
      var output = List.filled(521, 0.0).reshape([1, 521]);
      
      // Запуск инференса
      _interpreter!.run(input, output);
      
      // Проверяем класс "Dog" (индекс 151 в YAMNet)
      double dogScore = output[0][151];
      bool isDogBark = dogScore > 0.3; // Порог 30%
      
      print('Dog score: ${dogScore.toStringAsFixed(2)}');
      
      return {
        'isDogBark': isDogBark,
        'confidence': dogScore,
        'loudness': _calculateLoudness(audioData),
      };
    } catch (e) {
      print('Ошибка классификации: $e');
      return {'isDogBark': false, 'confidence': 0.0, 'error': e.toString()};
    }
  }

  // Подготовка входных данных
  List<List<double>> _prepareInput(List<double> audioData) {
    // YAMNet требует 15600 сэмплов (0.975 сек при 16kHz)
    const int requiredLength = 15600;
    
    List<double> processed = List.filled(requiredLength, 0.0);
    int copyLength = audioData.length < requiredLength ? audioData.length : requiredLength;
    
    for (int i = 0; i < copyLength; i++) {
      processed[i] = audioData[i];
    }
    
    return [processed];
  }

  // Расчет громкости (RMS)
  double _calculateLoudness(List<double> audioData) {
    double sum = 0.0;
    for (var sample in audioData) {
      sum += sample * sample;
    }
    return (sum / audioData.length).clamp(0.0, 1.0);
  }

  void dispose() {
    _interpreter?.close();
  }
}

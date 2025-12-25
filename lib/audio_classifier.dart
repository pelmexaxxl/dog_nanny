import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:math';

enum DetectionMode { economical, precise }

class AudioClassifier {
  Interpreter? _interpreter;
  DetectionMode _mode = DetectionMode.economical;

  Future<void> initialize() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/yamnet.tflite');
      print('YAMNet загружена');
    } catch (e) {
      print('Ошибка загрузки YAMNet: $e');
    }
  }

  void setMode(DetectionMode mode) {
    _mode = mode;
  }

  // ПРОСТАЯ FFT
  List<double> _simpleFFT(List<double> samples) {
    int n = samples.length;
    List<double> magnitudes = List.filled(n ~/ 2, 0.0);
    
    for (int k = 0; k < n ~/ 2; k++) {
      double real = 0;
      double imag = 0;
      
      for (int t = 0; t < n; t++) {
        double angle = -2 * pi * k * t / n;
        real += samples[t] * cos(angle);
        imag += samples[t] * sin(angle);
      }
      
      magnitudes[k] = sqrt(real * real + imag * imag);
    }
    
    return magnitudes;
  }

  // ЧАСТОТНЫЙ АНАЛИЗ
  Map<String, double> analyzeFrequencies(List<int> pcmData) {
    if (pcmData.length < 512) {
      return {'dominantFreq': 0, 'energy': 0, 'spectralCentroid': 0};
    }

    List<double> samples = pcmData.sublist(pcmData.length - 512)
        .map((s) => s / 32768.0).toList();

    List<double> magnitudes = _simpleFFT(samples);

    int maxIdx = 0;
    double maxMag = 0;
    for (int i = 1; i < magnitudes.length; i++) {
      if (magnitudes[i] > maxMag) {
        maxMag = magnitudes[i];
        maxIdx = i;
      }
    }
    
    double dominantFreq = (maxIdx * 16000) / 512.0;

    double energy = magnitudes.reduce((a, b) => a + b) / magnitudes.length;

    double numerator = 0;
    double denominator = 0;
    for (int i = 0; i < magnitudes.length; i++) {
      double freq = (i * 16000) / 512.0;
      numerator += freq * magnitudes[i];
      denominator += magnitudes[i];
    }
    double spectralCentroid = denominator > 0 ? numerator / denominator : 0;

    return {
      'dominantFreq': dominantFreq,
      'energy': energy,
      'spectralCentroid': spectralCentroid,
    };
  }

  // ML КЛАССИФИКАЦИЯ
  Future<Map<String, dynamic>> classify(List<int> pcmData) async {
    if (_interpreter == null) {
      return {'isDogBark': false, 'confidence': 0.0, 'method': 'no_model'};
    }

    var freqData = analyzeFrequencies(pcmData);
    double dominantFreq = freqData['dominantFreq']!;
    double energy = freqData['energy']!;
    double spectralCentroid = freqData['spectralCentroid']!;

    if (_mode == DetectionMode.economical) {
      // Экономный: строгий частотный анализ БЕЗ ML
      
      double freqRatio = spectralCentroid / (dominantFreq + 1);
      
      // КРИТЕРИИ ЛАЯ:
      // 1. Доминантная: 500-1500 Гц (средние частоты)
      // 2. Центроид: 1000-2000 Гц (узкий диапазон)
      // 3. Энергия: 1.0-4.5 (не слишком тихо/громко)
      // 4. Ratio: 1.3-2.2 (характерный для лая)
      
      bool isDogBark = 
        dominantFreq >= 500 && dominantFreq <= 1500 &&         
        spectralCentroid >= 1000 && spectralCentroid <= 2000 && 
        energy > 1.0 && energy < 4.5 &&                        
        freqRatio >= 1.3 && freqRatio <= 2.2;
      
      return {
        'isDogBark': isDogBark,
        'confidence': isDogBark ? 0.75 : 0.25,
        'method': 'frequency_analysis',
        'dominantFreq': dominantFreq.toInt(),
        'energy': (energy * 100).toStringAsFixed(1),
        'spectralCentroid': spectralCentroid.toInt(),
        'freqRatio': freqRatio.toStringAsFixed(2),
      };
    } else {
      // Точный: частоты + YAMNet (строгая комбинация)
      
      List<double> waveform = _prepareWaveform(pcmData);
      
      var input = [waveform];
      var output = List.filled(1 * 521, 0.0).reshape([1, 521]);
      
      try {
        _interpreter!.run(input, output);
        
        // YAMNet классы: 75 = Dog, 76 = Bark
        double dogConfidence = output[0][75];
        double barkConfidence = output[0].length > 76 ? output[0][76] : 0.0;
        double maxConfidence = dogConfidence > barkConfidence ? dogConfidence : barkConfidence;
        
        print('YAMNet scores - Dog: $dogConfidence, Bark: $barkConfidence');
        
        // СТРОГИЕ КРИТЕРИИ:
        // 1. Частоты идеальны (500-1800 Гц)
        // 2. Центроид в диапазоне (900-2200 Гц)  
        // 3. Энергия умеренная (0.5-5.0)
        // 4. ML ОБЯЗАТЕЛЬНО подтверждает (>0.08)

        bool freqMatch = dominantFreq >= 500 && dominantFreq <= 1800;
        bool centroidMatch = spectralCentroid >= 900 && spectralCentroid <= 2200;
        bool energyMatch = energy > 0.5 && energy < 5.0;
        bool mlConfirms = maxConfidence > 0.08;

        // ВСЕ 4 условия обязательны
        bool isDogBark = freqMatch && centroidMatch && energyMatch && mlConfirms;

        
        return {
          'isDogBark': isDogBark,
          'confidence': maxConfidence,
          'method': 'ml_yamnet',
          'dominantFreq': dominantFreq.toInt(),
          'energy': (energy * 100).toStringAsFixed(1),
          'spectralCentroid': spectralCentroid.toInt(),
          'mlScore': maxConfidence.toStringAsFixed(2),
          'dogScore': dogConfidence.toStringAsFixed(3),
          'barkScore': barkConfidence.toStringAsFixed(3),
        };
      } catch (e) {
        print('ML ошибка: $e');
        // Fallback на частоты (строгий)
        bool isDogBark = dominantFreq >= 500 && dominantFreq <= 1800 &&
                        spectralCentroid >= 900 && spectralCentroid <= 2200 &&
                        energy > 1.0 && energy < 5.0;
        return {
          'isDogBark': isDogBark,
          'confidence': 0.5,
          'method': 'frequency_fallback',
          'dominantFreq': dominantFreq.toInt(),
        };
      }
    }
  }

  List<double> _prepareWaveform(List<int> pcmData) {
    List<double> waveform = [];
    int targetLength = 15600;
    
    if (pcmData.length >= targetLength) {
      for (int i = pcmData.length - targetLength; i < pcmData.length; i++) {
        waveform.add(pcmData[i] / 32768.0);
      }
    } else {
      for (int i = 0; i < pcmData.length; i++) {
        waveform.add(pcmData[i] / 32768.0);
      }
      while (waveform.length < targetLength) {
        waveform.add(0.0);
      }
    }
    
    return waveform;
  }

  void dispose() {
    _interpreter?.close();
  }
}

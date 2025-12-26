import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:math';

enum DetectionMode { economical, precise }

const Map<int, String> kDogClasses = {
  69: 'Dog',
  70: 'Bark',
  71: 'Yip',
  72: 'Howl',
  73: 'Bow-wow',
  74: 'Growling',
  75: 'Whimper (dog)',
  117: 'Canidae, dogs, wolves',
};

String? topLabelFrom(Map<int, String> classes, List<double> probs, {double minScore = 0.0}) {
  int? bestIndex;
  double best = minScore;
  for (final i in classes.keys) {
    final v = probs[i];
    if (v > best) {
      best = v;
      bestIndex = i;
    }
  }
  return bestIndex == null ? null : classes[bestIndex];
}

double topScoreFrom(Map<int, String> classes, List<double> probs) {
  double best = 0.0;
  for (final i in classes.keys) {
    final v = probs[i];
    if (v > best) best = v;
  }
  return best;
}

double dogRelatedScore(List<double> probs) {
  double best = 0.0;
  for (final i in kDogClasses.keys) {
    final v = probs[i];
    if (v > best) best = v;
  }
  return best;
}

String? topDogLabel(List<double> probs, {double minScore = 0.0}) {
  int? bestIndex;
  double best = minScore;
  for (final i in kDogClasses.keys) {
    final v = probs[i];
    if (v > best) {
      best = v;
      bestIndex = i;
    }
  }
  return bestIndex == null ? null : kDogClasses[bestIndex];
}

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
      // Точный: YAMNet + минимальная проверка "не тишина"
      final List<double> waveform = _prepareWaveform(pcmData);

      final input = [waveform];
      final output = List.filled(1 * 521, 0.0).reshape([1, 521]);

      // Порог подбери под себя
      const double mlThreshold = 0.08;
      const double silenceEnergyThreshold = 0.2;

      // Более "конкретные" собачьи вокализации (чтобы чаще получать Bark/Howl/…)
      const Map<int, String> kDogVocalClasses = {
        70: 'Bark',
        71: 'Yip',
        72: 'Howl',
        73: 'Bow-wow',
        74: 'Growling',
        75: 'Whimper (dog)',
      };

      int? _topIndexFrom(Map<int, String> classes, List<double> probs) {
        int? bestIndex;
        double best = 0.0;
        for (final i in classes.keys) {
          final v = probs[i];
          if (v > best) {
            best = v;
            bestIndex = i;
          }
        }
        return bestIndex;
      }

      double _topScoreFrom(Map<int, String> classes, List<double> probs) {
        double best = 0.0;
        for (final i in classes.keys) {
          final v = probs[i];
          if (v > best) best = v;
        }
        return best;
      }

      try {
        _interpreter!.run(input, output);

        final List<double> probs = List<double>.from(output[0]); // 521 scores

        // Любой собачий звук (включая общие классы Dog/Canidae)
        final double anyDogScore = dogRelatedScore(probs);
        final String? anyDogLabel = topDogLabel(probs);

        // Попытка дать "более конкретное" описание: Bark/Howl/Growling/Whimper/...
        final int? vocalTopIndex = _topIndexFrom(kDogVocalClasses, probs);
        final double vocalTopScore = _topScoreFrom(kDogVocalClasses, probs);
        final String? vocalTopLabel =
            (vocalTopIndex == null) ? null : kDogVocalClasses[vocalTopIndex];

        final bool notSilent = energy > silenceEnergyThreshold;
        final bool mlConfirms = anyDogScore > mlThreshold;

        // Любой собачий звук
        final bool isDogBark = mlConfirms && notSilent;

        // Что именно распознано:
        // - если среди "вокализаций" уверенность хорошая, показываем её (Bark/Howl/…)
        // - иначе показываем более общий top label из dogRelated (может быть Dog/Canidae)
        final String? detectedLabel =
            (vocalTopLabel != null && vocalTopScore > mlThreshold)
                ? vocalTopLabel
                : anyDogLabel;

        print(
          'YAMNet dog-scores: anyDogScore=$anyDogScore anyDogLabel=$anyDogLabel '
          'vocalTop=$vocalTopLabel vocalScore=$vocalTopScore '
          'energy=$energy notSilent=$notSilent',
        );

        return {
          'isDogBark': isDogBark, // ключ можно оставить, чтобы не ломать UI
          'confidence': anyDogScore,
          'method': 'ml_yamnet',

          // "что именно" (лай/вой/рычание/скулёж/...)
          'dogSoundLabel': isDogBark ? detectedLabel : null,

          // отладка / аналитика
          'mlScore': anyDogScore.toStringAsFixed(3),
          'vocalLabel': vocalTopLabel,
          'vocalScore': vocalTopScore.toStringAsFixed(3),
          'notSilent': notSilent,

          // твои фичи (можно оставить для UI/логов)
          'dominantFreq': dominantFreq.toInt(),
          'energy': (energy * 100).toStringAsFixed(1),
          'spectralCentroid': spectralCentroid.toInt(),
        };
      } catch (e) {
        print('ML ошибка: $e');

        // Если ML упал, честнее вернуть "не могу классифицировать" (а не частотные эвристики под лай)
        return {
          'isDogBark': false,
          'confidence': 0.0,
          'method': 'ml_error',
          'dominantFreq': dominantFreq.toInt(),
          'energy': (energy * 100).toStringAsFixed(1),
          'spectralCentroid': spectralCentroid.toInt(),
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

# Dog Nanny - Мобильное приложение для мониторинга лая собак

Приложение для Android, использующее машинное обучение и частотный анализ для детекции лая собак в реальном времени.

---

## Описание

Dog Nanny отслеживает звуки в реальном времени и определяет лай собаки с помощью комбинации:
- FFT частотного анализа (доминантная частота, спектральный центроид, энергия)
- Машинного обучения YAMNet (TensorFlow Lite, 521 класс звуков)

Приложение предоставляет два режима детекции:
- Экономный режим - только частотный анализ, низкое энергопотребление
- Точный режим - комбинация FFT + ML, минимум ложных срабатываний

---

## Архитектура

Приложение построено по трёхуровневой архитектуре:

### UI Layer (main.dart)
- Интерфейс мониторинга с индикатором громкости
- Управление порогом детекции и переключение режимов
- История обнаруженных событий с возможностью удаления
- Статистика: подтверждённые лаи, ложные срабатывания, точность

### Business Logic Layer (audio_classifier.dart)
- FFT анализ аудиосигнала (512 samples)
- Извлечение частотных признаков
- ML классификация через YAMNet (классы Dog/Bark)
- Логика принятия решения на основе режима

### Data Layer
- Захват PCM аудио через mic_stream (16kHz mono)
- Загрузка и inference TFLite модели YAMNet (~5MB)

### Компонентная диаграмма

![Architecture Diagram](docs/architecture.png)

### Поток данных

![Data Flow Diagram](docs/data_flow.png)

### Диаграмма классов

![Class Diagram](docs/classes.png)

Исходные PlantUML файлы: `docs/*.puml`

---

## Режимы детекции

### Режим "Частоты" (Economical)
Использует только FFT анализ:
- Доминантная частота: 500-1500 Гц
- Спектральный центроид: 1000-2000 Гц
- Энергия сигнала: 1.0-4.5
- Frequency Ratio: 1.3-2.2

### Режим "ML+Частоты" (Precise)
Комбинирует частотный анализ и нейросеть:
- Частотные критерии (расширенные 500-1800 Гц)
- YAMNet confidence >0.08 для классов Dog (75) или Bark (76)
- Все критерии обязательны

---

## Метрики качества

### Performance
- Latency анализа: ~200-300ms
- Sample rate: 16kHz mono
- FFT size: 512 samples
- ML inference time: ~100ms

### Accuracy
Пользователь может удалять ложные срабатывания из истории.
Приложение автоматически рассчитывает:
- Подтверждённых лаев
- Ложных срабатываний (удалённых)
- Точность детекции в процентах

---

## Технологический стек

Framework: Flutter 3.5.3, Dart 3.5.3

Библиотеки:
- mic_stream: 0.7.2 - захват PCM аудио
- tflite_flutter: 0.11.0 - ML inference
- permission_handler: 10.4.5 - разрешения микрофона

ML Model: YAMNet (TensorFlow Lite, 521 класс, 5MB)

Platform: Android (minSdk 24, targetSdk 35, Java 17)

---

## Структура проекта

dog_nanny/
├── lib/
│ ├── main.dart # UI + мониторинг + статистика
│ └── audio_classifier.dart # FFT анализ + ML классификация
│
├── assets/
│ └── models/
│ └── yamnet.tflite # ML модель YAMNet (5MB)
│
├── android/
│ ├── app/
│ │ ├── build.gradle # Конфигурация сборки (Java 17)
│ │ └── proguard-rules.pro # Правила для TFLite
│ └── gradle.properties
│
├── docs/
│ └── architecture.puml # PlantUML диаграмма архитектуры
│
├── pubspec.yaml # Зависимости Flutter
└── README.md # Документация


---

## Сборка и установка

### Разработка (debug)

flutter run -d <device_id>

### Релиз (APK)

flutter build apk --release --split-per-abi

Результат:
- build/app/outputs/apk/release/app-arm64-v8a-release.apk (64-bit, ~20MB)
- build/app/outputs/apk/release/app-armeabi-v7a-release.apk (32-bit, ~18MB)

---

## Quality Assurance

### Testing Model
- Functional Testing: детекция лая, фильтрация музыки/речи/шума
- Usability Testing: пользовательская оценка через удаление ложных
- Performance Testing: измерение latency обработки

### User Feedback Mechanism
Каждое обнаруженное событие сохраняется в истории с временем и кнопкой удаления.
Удаление записи:
- Уменьшает счётчик подтверждённых лаев
- Увеличивает счётчик ложных срабатываний
- Пересчитывает метрику точности



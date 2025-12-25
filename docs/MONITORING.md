# Monitoring Documentation - Dog Nanny

Система мониторинга приложения для отслеживания ключевых метрик качества и надёжности.

---

## Key Metrics

### Reliability Metrics

**Crash Rate**
- Отслеживаемая метрика: количество критических ошибок
- Инструмент: встроенный AppMonitoring класс
- Лог: errors логируются с timestamp и stack trace
- Хранение: локальный файл monitoring_metrics.txt

**Accuracy Rate**
- Формула: (Confirmed Detections / Total Detections) × 100%
- Цель: >= 80%
- Обновление: в реальном времени при каждой детекции

**False Positive Rate**
- Формула: (False Positives / Total Detections) × 100%
- Цель: <= 20%
- Обновление: при удалении пользователем

---

## Monitoring Tool

**AppMonitoring Class** - встроенная система мониторинга

Компоненты:
- Session tracking (старт/стоп сессии)
- Detection logging (каждая детекция с метаданными)
- Error logging (crashes и exceptions)
- Metrics persistence (сохранение в файл)

Расположение: lib/monitoring.dart

---

## Tracked Events

### Session Events
- SESSION_START: начало сессии мониторинга
- SESSION_END: завершение с длительностью

### Detection Events
- Каждая детекция логируется с:
  - timestamp
  - is_dog_bark (true/false)
  - metadata (method, confidence, frequency)

### Error Events
- Любые exceptions в try-catch блоках
- Stack trace для debugging

---

## Metrics Report

Доступ: кнопка "Отчёт мониторинга" в UI

Отображаемые метрики:
- Количество сессий
- Всего детекций
- Подтверждённых лаев
- Ложных срабатываний
- Точность (%)
- False Positive Rate (%)
- Количество crashes

Экспорт: автоматическое сохранение в monitoring_metrics.txt

---

## Storage

**Location:** 
- Android: /data/data/com.example.dog_nanny/files/monitoring_metrics.txt

**Format:** Plain text report

**Persistence:** Метрики сохраняются при каждом изменении

---

## Integration

Мониторинг интегрирован в жизненный цикл приложения:

App Start → startSession()
Detection → logDetection()
User Removes → logFalsePositive()
Error occurs → logError()
App Close → endSession()

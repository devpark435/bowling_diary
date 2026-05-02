import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

// 파싱 로직 직접 테스트용 헬퍼 (API 호출 없음)
Map<String, dynamic>? _parseGeminiJson(String responseBody) {
  try {
    final json = jsonDecode(responseBody);
    final text = json['candidates'][0]['content']['parts'][0]['text'] as String;
    return jsonDecode(text) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

double? _calcSpeed({
  required int? foulLineFrame,
  required int? arrowsFrame,
  required int? headpinFrame,
  required double intervalSec,
}) {
  int? startFrame, endFrame;
  double? distance;

  if (foulLineFrame != null && headpinFrame != null && headpinFrame > foulLineFrame) {
    startFrame = foulLineFrame; endFrame = headpinFrame; distance = 18.29;
  } else if (foulLineFrame != null && arrowsFrame != null && arrowsFrame > foulLineFrame) {
    startFrame = foulLineFrame; endFrame = arrowsFrame; distance = 4.57;
  } else if (arrowsFrame != null && headpinFrame != null && headpinFrame > arrowsFrame) {
    startFrame = arrowsFrame; endFrame = headpinFrame; distance = 13.72;
  }

  if (startFrame == null || endFrame == null || distance == null) return null;
  final elapsed = (endFrame - startFrame) * intervalSec;
  final minElapsed = distance / (50.0 / 3.6);
  final maxElapsed = distance / (10.0 / 3.6);
  if (elapsed < minElapsed || elapsed > maxElapsed) return null;
  return double.parse(((distance / elapsed) * 3.6).toStringAsFixed(1));
}

double? _calcRpm({required double? rotationCount, required int cropFrameCount, required double cropIntervalSec}) {
  if (rotationCount == null || rotationCount <= 0 || cropFrameCount <= 1) return null;
  final durationSec = (cropFrameCount - 1) * cropIntervalSec;
  final rawRpm = (rotationCount / durationSec) * 60;
  if (rawRpm < 50 || rawRpm > 500) return null;
  return rawRpm;
}

void main() {
  group('_parseGeminiJson', () {
    test('정상 응답 파싱', () {
      final body = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'text': jsonEncode({
                    'foul_line_frame': 5,
                    'arrows_frame': 8,
                    'headpin_frame': 18,
                    'rotation_count': 3.5,
                  })
                }
              ]
            }
          }
        ]
      });
      final result = _parseGeminiJson(body);
      expect(result, isNotNull);
      expect(result!['foul_line_frame'], equals(5));
      expect(result['rotation_count'], equals(3.5));
    });

    test('빈/잘못된 응답 → null', () {
      expect(_parseGeminiJson('{}'), isNull);
      expect(_parseGeminiJson('invalid'), isNull);
    });
  });

  group('_calcSpeed', () {
    test('파울라인↔헤드핀 → 18.29m 기준 계산', () {
      // 프레임 5→18, 간격 0.2s → elapsed=2.6s → 18.29/2.6*3.6=25.3 km/h
      final speed = _calcSpeed(
        foulLineFrame: 5,
        arrowsFrame: null,
        headpinFrame: 18,
        intervalSec: 0.2,
      );
      expect(speed, isNotNull);
      expect(speed!, closeTo(25.3, 0.5));
    });

    test('랜드마크 모두 null → null', () {
      final speed = _calcSpeed(
        foulLineFrame: null, arrowsFrame: null, headpinFrame: null, intervalSec: 0.1);
      expect(speed, isNull);
    });

    test('elapsed 범위 초과 → null', () {
      // 18.29m / 0.1s = 658 km/h → 범위 초과
      final speed = _calcSpeed(
        foulLineFrame: 0, arrowsFrame: null, headpinFrame: 1, intervalSec: 0.1);
      expect(speed, isNull);
    });

    test('화살표↔헤드핀 폴백', () {
      // arrows=5, headpin=18, interval=0.3s → elapsed=3.9s → 13.72/3.9*3.6=12.7 km/h ✓
      final speed = _calcSpeed(
        foulLineFrame: null, arrowsFrame: 5, headpinFrame: 18, intervalSec: 0.3);
      expect(speed, isNotNull);
    });
  });

  group('_calcRpm', () {
    test('3회전 / 0.5s = 360 RPM', () {
      // 3 / (15 * 1/30) * 60 = 3/0.5*60 = 360
      final rpm = _calcRpm(rotationCount: 3.0, cropFrameCount: 16, cropIntervalSec: 1/30);
      expect(rpm, isNotNull);
      expect(rpm!, closeTo(360, 1));
    });

    test('0회전 → null', () {
      expect(_calcRpm(rotationCount: 0.0, cropFrameCount: 10, cropIntervalSec: 1/30), isNull);
    });

    test('600 RPM 범위 초과 → null', () {
      final rpm = _calcRpm(rotationCount: 10.0, cropFrameCount: 31, cropIntervalSec: 1/30);
      expect(rpm, isNull);
    });
  });
}

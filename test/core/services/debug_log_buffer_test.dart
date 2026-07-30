import 'package:bowling_diary/core/services/debug_log_buffer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DebugLogBuffer 적재', () {
    test('capacity 이내면 전부 보관한다', () {
      final buffer = DebugLogBuffer(capacity: 5);
      for (var i = 0; i < 5; i++) {
        buffer.add('line$i');
      }
      expect(buffer.length, 5);
      expect(buffer.dump(), 'line0\nline1\nline2\nline3\nline4');
    });

    test('capacity를 넘으면 오래된 줄부터 버린다', () {
      final buffer = DebugLogBuffer(capacity: 3);
      for (var i = 0; i < 10; i++) {
        buffer.add('line$i');
      }
      expect(buffer.length, 3);
      expect(buffer.dump(), 'line7\nline8\nline9');
    });

    test('clear는 버퍼를 비운다', () {
      final buffer = DebugLogBuffer(capacity: 3)..add('a');
      buffer.clear();
      expect(buffer.length, 0);
      expect(buffer.dump(), '');
    });
  });

  group('DebugLogBuffer.dump 절단', () {
    test('maxChars 이내면 그대로 반환한다', () {
      final buffer = DebugLogBuffer()..add('짧은 줄');
      expect(buffer.dump(maxChars: 100), '짧은 줄');
    });

    test('maxChars를 넘으면 앞이 아니라 뒤를 남긴다', () {
      // 실패 직전 줄이 진단에 가장 중요하므로 tail 보존이 요구사항이다.
      final buffer = DebugLogBuffer();
      for (var i = 0; i < 100; i++) {
        buffer.add('x' * 20);
      }
      buffer.add('MARKER_마지막줄');

      final dumped = buffer.dump(maxChars: 50);
      expect(dumped, contains('MARKER_마지막줄'));
      expect(dumped, startsWith('…(앞부분 '));
      expect(dumped.endsWith('MARKER_마지막줄'), isTrue);
    });
  });

  group('DebugLogBuffer.install', () {
    test('debugPrint 출력을 전역 인스턴스에 적재하고 원래 출력도 통과시킨다', () {
      final original = debugPrint;
      final passedThrough = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) passedThrough.add(message);
      };

      DebugLogBuffer.install();
      DebugLogBuffer.instance.clear();
      debugPrint('[Test] 진단 한 줄');

      expect(DebugLogBuffer.instance.dump(), contains('[Test] 진단 한 줄'));
      expect(passedThrough, contains('[Test] 진단 한 줄'));

      debugPrint = original;
    });

    test('중복 install해도 래퍼가 겹쳐 쌓이지 않는다', () {
      final original = debugPrint;
      final passedThrough = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) passedThrough.add(message);
      };

      DebugLogBuffer.install();
      DebugLogBuffer.install();
      DebugLogBuffer.instance.clear();
      debugPrint('중복');

      // 래퍼가 두 겹이면 원래 출력이 2번 호출되고 버퍼에도 2줄이 쌓인다.
      expect(passedThrough.where((l) => l == '중복').length, 1);
      expect(DebugLogBuffer.instance.length, 1);

      debugPrint = original;
    });
  });
}

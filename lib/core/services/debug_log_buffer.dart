import 'package:flutter/foundation.dart';

/// `debugPrint` 출력을 메모리에 모아두는 링 버퍼.
///
/// 분석 파이프라인은 진단에 결정적인 정보를 전부 `debugPrint`로만 뱉는다
/// (`[FrameExtractor] 추출 완료`, `[BallDetection] 검출 N/M ... 최고 점수`,
/// `[PinZone] 소스`, `[Trajectory] 리본 소스`, `[Speed] 랜드마크/기존/채택`).
/// TestFlight 빌드에는 콘솔이 없어 이게 전부 사라지므로, 실패·성공 시점에
/// 서버로 올릴 수 있도록 최근 [capacity]줄을 붙잡아둔다.
///
/// 내부 QA 전용 — 공개 배포 전 제거 대상.
class DebugLogBuffer {
  DebugLogBuffer({this.capacity = 400});

  /// 보관할 최대 줄 수. 분석 1회가 뱉는 줄 수(수십~200여 줄)를 넉넉히 덮는다.
  final int capacity;

  final List<String> _lines = <String>[];

  static final DebugLogBuffer instance = DebugLogBuffer();

  static DebugPrintCallback? _wrapper;

  /// 전역 `debugPrint`를 감싸 버퍼에 적재한다. 원래 출력은 그대로 통과시킨다.
  ///
  /// 이미 우리 래퍼가 걸려 있으면 아무것도 하지 않는다 — 중복 호출로 래퍼가
  /// 겹겹이 쌓이면 한 줄이 여러 번 적재되고 원래 출력도 중복된다.
  static void install() {
    if (identical(debugPrint, _wrapper)) return;
    final previous = debugPrint;
    _wrapper = (String? message, {int? wrapWidth}) {
      if (message != null) instance.add(message);
      previous(message, wrapWidth: wrapWidth);
    };
    debugPrint = _wrapper!;
  }

  int get length => _lines.length;

  void add(String line) {
    _lines.add(line);
    if (_lines.length > capacity) {
      _lines.removeRange(0, _lines.length - capacity);
    }
  }

  void clear() => _lines.clear();

  /// 버퍼 내용을 하나의 문자열로. [maxChars]를 넘으면 **뒤쪽을 남긴다** —
  /// 실패 직전 줄이 가장 중요하기 때문.
  String dump({int maxChars = 60000}) {
    final joined = _lines.join('\n');
    if (joined.length <= maxChars) return joined;
    return '…(앞부분 ${joined.length - maxChars}자 생략)\n'
        '${joined.substring(joined.length - maxChars)}';
  }
}

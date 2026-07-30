import 'dart:io';

import 'package:bowling_diary/features/analysis/domain/services/arrow_detector.dart';
import 'package:bowling_diary/features/analysis/domain/services/lane_landmark_speed.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 실촬영 프레임에 대한 화살표 검출기 탐침 — 정식 테스트가 아니라 조사용이다.
/// 이미지가 없으면 조용히 통과한다(CI/타 머신에서 깨지지 않게).
const _dir = '/Users/parkhyunryeol/.claude/jobs/c9e42aa7/tmp';

void main() {
  test('실촬영 첫 프레임 3방향 화살표 검출', () {
    for (final name in ['lm_land', 'lm_cw', 'lm_ccw', 'lm_bg']) {
      final file = File('$_dir/$name.jpg');
      if (!file.existsSync()) {
        // ignore: avoid_print
        print('$name: 파일 없음 — 건너뜀');
        continue;
      }
      final frame = img.decodeImage(file.readAsBytesSync())!;
      final arrows = detectArrows(frame);
      // ignore: avoid_print
      print('$name (${frame.width}x${frame.height}): 검출 ${arrows.length}개 '
          '${arrows.map((a) => '(${a.nx.toStringAsFixed(3)},${a.ny.toStringAsFixed(3)})').join(' ')}');
      final line = arrowLineFromDetections(arrows);
      // ignore: avoid_print
      print('   선: ${line == null ? '실패' : '성립 uM=${line.uM}'}');
    }
  });
}

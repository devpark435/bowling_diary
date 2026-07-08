import 'package:bowling_diary/features/analysis/domain/entities/drift_check_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';
import 'package:bowling_diary/features/analysis/presentation/utils/speed_failure_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('재캘리브레이션 필요 시 카메라 위치 안내', () {
    final msg = speedFailureUserMessage(null, DriftStatus.recalibrationRequired);
    expect(msg, contains('카메라 위치'));
  });

  test('검출 실패 계열은 조명 안내', () {
    final msg = speedFailureUserMessage(SpeedFailure.releaseNotFound, DriftStatus.ok);
    expect(msg, contains('인식하지 못했'));
  });

  test('신호 불일치 계열은 재촬영 안내, enum 이름 노출 안 함', () {
    final msg = speedFailureUserMessage(SpeedFailure.anchorMismatch, DriftStatus.ok);
    expect(msg, contains('다시 촬영'));
    expect(msg, isNot(contains('anchorMismatch')));
  });

  test('성공(null failure, drift ok)이면 빈 문자열', () {
    final msg = speedFailureUserMessage(null, DriftStatus.ok);
    expect(msg, isEmpty);
  });
}

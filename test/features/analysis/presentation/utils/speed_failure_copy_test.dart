import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';
import 'package:bowling_diary/features/analysis/presentation/utils/speed_failure_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('검출 실패 계열은 조명 안내', () {
    final msg = speedFailureUserMessage(SpeedFailure.releaseNotFound);
    expect(msg, contains('인식하지 못했'));
  });

  test('신호 불일치 계열은 재촬영 안내, enum 이름 노출 안 함', () {
    final msg = speedFailureUserMessage(SpeedFailure.anchorMismatch);
    expect(msg, contains('다시 촬영'));
    expect(msg, isNot(contains('anchorMismatch')));
  });

  test('성공(null failure)이면 빈 문자열', () {
    final msg = speedFailureUserMessage(null);
    expect(msg, isEmpty);
  });

  group('speedConfidenceBadgeLabel', () {
    test('0.75 이상은 신뢰도 높음 (경계 포함)', () {
      expect(speedConfidenceBadgeLabel(0.90), '신뢰도 높음');
      expect(speedConfidenceBadgeLabel(0.75), '신뢰도 높음');
    });

    test('0.5~0.75는 신뢰도 보통 (하한 경계 포함)', () {
      expect(speedConfidenceBadgeLabel(0.74), '신뢰도 보통');
      expect(speedConfidenceBadgeLabel(0.5), '신뢰도 보통');
    });

    test('0.5 미만은 참고용', () {
      expect(speedConfidenceBadgeLabel(0.49), '참고용');
      expect(speedConfidenceBadgeLabel(0.0), '참고용');
    });
  });
}

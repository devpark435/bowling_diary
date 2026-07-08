import 'dart:convert';
import 'dart:io';

import 'package:bowling_diary/features/analysis/data/services/analysis_pipeline.dart';
import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/speed_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixturesDir = Directory('test/golden_reference/fixtures');
  final mp4Files = fixturesDir.existsSync()
      ? fixturesDir.listSync().whereType<File>().where((f) => f.path.endsWith('.mp4')).toList()
      : <File>[];

  if (mp4Files.isEmpty) {
    test('골든 레퍼런스 fixture 없음 — 회귀 테스트 skip', () {}, skip: 'test/golden_reference/fixtures/에 fixture를 추가하면 실행됨');
    return;
  }

  for (final mp4 in mp4Files) {
    final name = mp4.uri.pathSegments.last.replaceAll('.mp4', '');
    test('$name 속도 회귀 비교', () async {
      // fixture는 기존 캘리브레이션 프로파일 JSON 포맷을 그대로 유지한다(homography
      // 배열 외 필드는 저장형 캘리브레이션 폐기 후 더 이상 쓰이지 않지만 무시하면 됨).
      final calibJson = jsonDecode(
        File('${fixturesDir.path}/$name.calibration.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final expected = jsonDecode(
        File('${fixturesDir.path}/$name.expected.json').readAsStringSync(),
      ) as Map<String, dynamic>;

      final homography = HomographyMatrix.fromRowMajor(
        (calibJson['homography'] as List).map((e) => (e as num).toDouble()).toList(),
      );

      final pipeline = AnalysisPipeline(
        frameExtractor: VideoFrameExtractorService(),
        ballDetector: BallDetectionService(),
        releaseDetector: ReleaseDetectorService(),
        impactDetector: ImpactDetectorService(pinImpactDetector: PinImpactDetectorService()),
        speedEstimator: SpeedEstimatorService(),
      );

      final result = await pipeline.run(mp4.path, homography);
      final groundTruth = (expected['groundTruthKmh'] as num).toDouble();
      final tolerance = (expected['toleranceKmh'] as num).toDouble();

      expect(result.speedKmh, isNotNull, reason: '측정 실패: ${result.speedFailure}');
      expect(result.speedKmh!, closeTo(groundTruth, tolerance));
    });
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:bowling_diary/features/analysis/data/services/analysis_pipeline.dart';
import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/speed_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/calibration_profile.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:bowling_diary/features/analysis/domain/services/calibration_drift_checker.dart';
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
      final calibJson = jsonDecode(
        File('${fixturesDir.path}/$name.calibration.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final expected = jsonDecode(
        File('${fixturesDir.path}/$name.expected.json').readAsStringSync(),
      ) as Map<String, dynamic>;

      final homography = HomographyMatrix.fromRowMajor(
        (calibJson['homography'] as List).map((e) => (e as num).toDouble()).toList(),
      );
      final framePoints = (calibJson['framePoints'] as List)
          .map((e) => FramePoint(nx: (e['nx'] as num).toDouble(), ny: (e['ny'] as num).toDouble()))
          .toList();
      final profile = CalibrationProfile(
        id: calibJson['id'] as String,
        name: calibJson['name'] as String,
        viewpoint: CameraViewpoint.values.firstWhere((v) => v.name == calibJson['viewpoint']),
        homography: homography,
        createdAt: DateTime.parse(calibJson['createdAt'] as String),
        referenceImagePath: calibJson['referenceImagePath'] as String,
        framePoints: framePoints,
      );

      final pipeline = AnalysisPipeline(
        frameExtractor: VideoFrameExtractorService(),
        ballDetector: BallDetectionService(),
        releaseDetector: ReleaseDetectorService(),
        impactDetector: ImpactDetectorService(pinImpactDetector: PinImpactDetectorService()),
        speedEstimator: SpeedEstimatorService(),
        driftChecker: CalibrationDriftChecker(),
      );

      final result = await pipeline.run(mp4.path, profile);
      final groundTruth = (expected['groundTruthKmh'] as num).toDouble();
      final tolerance = (expected['toleranceKmh'] as num).toDouble();

      expect(result.speedKmh, isNotNull, reason: '측정 실패: ${result.speedFailure}');
      expect(result.speedKmh!, closeTo(groundTruth, tolerance));
    });
  }
}

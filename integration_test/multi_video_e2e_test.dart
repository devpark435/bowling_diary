import 'dart:io';

import 'package:bowling_diary/features/analysis/data/services/analysis_pipeline.dart';
import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/rpm_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/speed_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 디렉토리 안 모든 .mp4를 순회하며 AnalysisPipeline 실행 + 결과 출력.
///
/// 실행:
///   `flutter test integration_test/multi_video_e2e_test.dart \`
///   `  -d <iOS Simulator> \`
///   `  --dart-define=TEST_VIDEO_DIR=/absolute/path/to/dir`
const _videoDir = String.fromEnvironment('TEST_VIDEO_DIR', defaultValue: '');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('다중 영상 배치 분석', (tester) async {
    if (_videoDir.isEmpty) {
      throw StateError('TEST_VIDEO_DIR dart-define 누락');
    }
    final dir = Directory(_videoDir);
    if (!await dir.exists()) {
      throw StateError('디렉토리 없음: $_videoDir');
    }

    final files = (await dir.list().toList())
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.mp4'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    if (files.isEmpty) {
      throw StateError('mp4 파일 없음: $_videoDir');
    }

    // ignore: avoid_print
    print('[BATCH] ${files.length}개 영상 분석 시작');

    final pipeline = AnalysisPipeline(
      frameExtractor: VideoFrameExtractorService(),
      ballDetector: BallDetectionService(),
      releaseDetector: ReleaseDetectorService(),
      impactDetector: PinImpactDetectorService(),
      speedEstimator: SpeedEstimatorService(),
      rpmEstimator: RpmEstimatorService(),
    );

    final results = <String, String>{};
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      // ignore: avoid_print
      print('\n========= [$name] =========');
      try {
        final data = await pipeline.run(file.path, 30);
        final summary = 'frames=${data.framesAnalyzed}, '
            'speed=${data.speedKmh}km/h(conf=${data.speedConfidence.toStringAsFixed(2)}, '
            'fail=${data.speedFailure}), '
            'rpm=${data.rpmEstimated}(conf=${data.rpmConfidence.toStringAsFixed(2)}, '
            'fail=${data.rpmFailure})';
        // ignore: avoid_print
        print('[BATCH][$name] $summary');
        results[name] = summary;
      } catch (e, st) {
        // ignore: avoid_print
        print('[BATCH][$name] 예외: $e\n$st');
        results[name] = 'ERROR: $e';
      }
    }

    // ignore: avoid_print
    print('\n========= 배치 결과 요약 =========');
    results.forEach((name, summary) {
      // ignore: avoid_print
      print('[$name] $summary');
    });
  }, timeout: const Timeout(Duration(minutes: 15)));
}

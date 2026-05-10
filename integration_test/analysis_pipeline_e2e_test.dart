import 'dart:io';

import 'package:bowling_diary/features/analysis/data/services/analysis_pipeline.dart';
import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/rpm_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/speed_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// 실제 영상으로 AnalysisPipeline 전체 동작 검증.
///
/// 실행:
///   `flutter test integration_test/analysis_pipeline_e2e_test.dart \`
///   `  -d {iOS Simulator | iPhone | Android emulator} \`
///   `  --dart-define=TEST_VIDEO=/absolute/path/to/testvideo.mp4`
///
/// iOS Simulator는 호스트 파일시스템을 직접 읽을 수 있어 절대 경로 가능.
/// 실기기는 영상을 앱 sandbox에 미리 푸시해야 함.
const _videoPath = String.fromEnvironment('TEST_VIDEO', defaultValue: '');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('AnalysisPipeline e2e — 실제 영상', () {
    late AnalysisPipeline pipeline;

    setUp(() {
      pipeline = AnalysisPipeline(
        frameExtractor: VideoFrameExtractorService(),
        ballDetector: BallDetectionService(),
        releaseDetector: ReleaseDetectorService(),
        // TODO(Phase 1.2): CalibrationRepository.getDefault()으로부터 HomographyMatrix 로드.
        // 현재는 identity matrix로 fallback (캘리브레이션 UI 미구현 상태).
        homography: HomographyMatrix.identity(),
        speedEstimator: SpeedEstimatorService(),
        rpmEstimator: RpmEstimatorService(),
      );
    });

    testWidgets('파이프라인 전체 실행 → 결과 합리적', (tester) async {
      final path = await _resolveVideoPath();

      final data = await pipeline.run(path, 30);

      // ignore: avoid_print
      print('[E2E] frames=${data.framesAnalyzed}, fps=${data.fpsUsed}, '
          'speed=${data.speedKmh}, rpm=${data.rpmEstimated}, '
          'speedFail=${data.speedFailure}, rpmFail=${data.rpmFailure}, '
          'speedConf=${data.speedConfidence}, rpmConf=${data.rpmConfidence}');

      expect(data.framesAnalyzed, greaterThan(0),
          reason: '프레임 추출 실패');
      expect(data.fpsUsed, greaterThan(0));

      // 속도/회전은 영상 품질에 따라 실패할 수 있음 — null 또는 합리적 범위
      if (data.speedKmh != null) {
        expect(data.speedKmh, inInclusiveRange(10, 50));
      }
      if (data.rpmEstimated != null) {
        expect(data.rpmEstimated, inInclusiveRange(100, 600));
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    testWidgets('진단: detection 분포 + release 이후 통계', (tester) async {
      final path = await _resolveVideoPath();

      final extractor = VideoFrameExtractorService();
      final detector = BallDetectionService();
      final releaseDet = ReleaseDetectorService();

      final extracted = await extractor.extract(path);
      final frames = extracted.frames;
      final w = frames.isNotEmpty ? frames.first.width : 0;
      final h = frames.isNotEmpty ? frames.first.height : 0;

      await detector.init();
      final detections = frames.map(detector.detect).toList();
      detector.dispose();

      final release = releaseDet.findRelease(detections);
      final afterRelease = detections.skip(release.frame).toList();
      final detectedAfter =
          afterRelease.whereType<BallDetection>().toList();
      final firstAfter =
          afterRelease.indexWhere((d) => d != null);
      final lastAfter =
          afterRelease.lastIndexWhere((d) => d != null);

      // ignore: avoid_print
      print('[DIAG] 영상=$w×$h, frames=${frames.length}, '
          'release=${release.frame}(conf=${release.confidence}), '
          'detection총=${detections.where((d) => d != null).length}/${detections.length}, '
          'release후detection=${detectedAfter.length}/${afterRelease.length}, '
          '첫감지=${firstAfter}, 마지막감지=${lastAfter}');

      if (detectedAfter.isNotEmpty) {
        final last = detectedAfter.last;
        final first = detectedAfter.first;
        // ignore: avoid_print
        print('[DIAG] release첫감지=(cx=${first.cx.toStringAsFixed(3)}, cy=${first.cy.toStringAsFixed(3)}, bw=${first.bw.toStringAsFixed(3)}, bh=${first.bh.toStringAsFixed(3)}, conf=${first.confidence.toStringAsFixed(2)})');
        // ignore: avoid_print
        print('[DIAG] release마지막감지=(cx=${last.cx.toStringAsFixed(3)}, cy=${last.cy.toStringAsFixed(3)}, bw=${last.bw.toStringAsFixed(3)}, bh=${last.bh.toStringAsFixed(3)}, conf=${last.confidence.toStringAsFixed(2)})');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    testWidgets('동일 영상 2회 실행 → 동일 결과 (결정성)', (tester) async {
      final path = await _resolveVideoPath();

      final d1 = await pipeline.run(path, 30);
      final d2 = await pipeline.run(path, 30);

      expect(d1.framesAnalyzed, equals(d2.framesAnalyzed));
      expect(d1.fpsUsed, equals(d2.fpsUsed));
      expect(d1.speedKmh, equals(d2.speedKmh));
      expect(d1.rpmEstimated, equals(d2.rpmEstimated));
      expect(d1.speedFailure, equals(d2.speedFailure));
      expect(d1.rpmFailure, equals(d2.rpmFailure));
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}

/// TEST_VIDEO env가 절대 경로면 그대로 반환.
/// iOS 실기기에서는 host fs 접근 불가 → asset bundle에 fallback (asset 미등록 시 throw).
Future<String> _resolveVideoPath() async {
  if (_videoPath.isEmpty) {
    throw StateError('TEST_VIDEO dart-define 누락. '
        '실행 시 --dart-define=TEST_VIDEO=<절대경로> 추가 필요.');
  }

  // 호스트 절대경로가 시뮬레이터에서 직접 접근 가능한 경우
  final hostFile = File(_videoPath);
  if (await hostFile.exists()) {
    return _videoPath;
  }

  // 실기기 fallback: asset bundle에서 임시 디렉토리로 복사
  // (실기기 사용 시에만 asset 추가 필요)
  try {
    final bytes = await rootBundle.load(_videoPath);
    final tempDir = await getTemporaryDirectory();
    final dst = File('${tempDir.path}/e2e_video.mp4');
    await dst.writeAsBytes(bytes.buffer.asUint8List());
    return dst.path;
  } catch (e) {
    throw StateError('영상 경로 해석 실패: $_videoPath ($e)');
  }
}


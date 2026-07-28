import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class FrameExtractionResult {
  final List<img.Image> frames;
  final int originalFps;
  final int sampleFps;

  const FrameExtractionResult({
    required this.frames,
    required this.originalFps,
    required this.sampleFps,
  });
}

class VideoFrameExtractorService {
  static const _sampleFps = 30;
  static const _maxFrames = 210; // 최대 7초 × 30fps — 실측 트림 영상 7.1초, 5초 캡이면
  // 느린 공의 핀 임팩트가 분석 창 밖으로 잘린다. 메모리 영향: 480x853 RGB ≈
  // 1.2MB/frame × 60 추가 ≈ +72MB 피크 — 분석 중 일시적이라 수용.
  // 연속 중복 프레임 판정: 리사이즈 후 평균 휘도차가 이 미만이면 동일 프레임으로 본다.
  static const _duplicateFrameLumaThreshold = 1.0;

  Future<FrameExtractionResult> extract(String videoPath) async {
    await _logSourceMeta(videoPath);
    final originalFps = await _getVideoFps(videoPath);

    final tempDir = await getTemporaryDirectory();
    final framesDir = Directory(
      '${tempDir.path}/frames_${DateTime.now().millisecondsSinceEpoch}',
    );
    await framesDir.create();

    try {
      final outputPattern = '${framesDir.path}/frame_%04d.jpg';
      final session = await FFmpegKit.execute(
        '-i "$videoPath" -vf "fps=$_sampleFps,scale=480:-1" -q:v 5 -frames:v $_maxFrames "$outputPattern"',
      );
      final returnCode = await session.getReturnCode();

      if (returnCode == null || !returnCode.isValueSuccess()) {
        final logs = await session.getLogs();
        debugPrint('[FrameExtractor] ffmpeg 오류: ${logs.map((l) => l.getMessage()).join('\n')}');
        throw Exception('프레임 추출 실패 (returnCode: $returnCode)');
      }

      final frameFiles = framesDir.listSync()
        ..sort((a, b) => a.path.compareTo(b.path));

      final frames = <img.Image>[];
      for (final file in frameFiles) {
        if (file is File && file.path.endsWith('.jpg')) {
          final bytes = await file.readAsBytes();
          final image = img.decodeImage(bytes);
          if (image != null) frames.add(image);
        }
      }

      debugPrint('[FrameExtractor] 추출 완료: ${frames.length}개 프레임, 원본 ${originalFps}fps, 샘플 ${_sampleFps}fps');
      _logDuplicateFrames(frames);
      return FrameExtractionResult(
        frames: frames,
        originalFps: originalFps,
        sampleFps: _sampleFps,
      );
    } finally {
      await framesDir.delete(recursive: true);
    }
  }

  Future<int> _getVideoFps(String videoPath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(videoPath);
      final streams = session.getMediaInformation()?.getStreams();
      if (streams != null) {
        for (final stream in streams) {
          if (stream.getType() == 'video') {
            final fpsStr = stream.getAverageFrameRate();
            if (fpsStr != null) {
              final parts = fpsStr.split('/');
              if (parts.length == 2) {
                final num = int.tryParse(parts[0]) ?? 30;
                final den = int.tryParse(parts[1]) ?? 1;
                return den > 0 ? (num / den).round() : 30;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[FrameExtractor] fps 감지 실패: $e');
    }
    return 30;
  }

  /// 시간축 왜곡(카톡 전송본 등에서 CFR 변환 시 프레임 재라벨) 계측용 로그.
  /// 소스의 duration/avg_frame_rate/r_frame_rate/nb_frames와 nb_frames÷duration로
  /// 구한 "실효 fps"를 남긴다. 동작에는 영향 없음 — 왜곡 여부 진단 전용.
  Future<void> _logSourceMeta(String videoPath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(videoPath);
      final info = session.getMediaInformation();

      final durationStr = info?.getDuration();
      final duration = durationStr != null ? double.tryParse(durationStr) : null;

      String? avgFrameRateStr;
      String? rFrameRateStr;
      String? nbFramesStr;
      final streams = info?.getStreams();
      if (streams != null) {
        for (final stream in streams) {
          if (stream.getType() == 'video') {
            avgFrameRateStr = stream.getAverageFrameRate();
            rFrameRateStr = stream.getRealFrameRate();
            nbFramesStr = stream.getStringProperty('nb_frames');
            break;
          }
        }
      }

      final avgFps = _parseFraction(avgFrameRateStr);
      final nbFrames = nbFramesStr != null ? int.tryParse(nbFramesStr) : null;
      final effectiveFps = (duration != null && duration > 0 && nbFrames != null)
          ? nbFrames / duration
          : null;

      debugPrint(
        '[FrameExtractor] 소스 메타: '
        'duration=${duration != null ? '${duration.toStringAsFixed(2)}s' : '?'}, '
        'avg_frame_rate=${avgFrameRateStr ?? '?'}(=${avgFps != null ? avgFps.toStringAsFixed(2) : '?'}), '
        'r_frame_rate=${rFrameRateStr ?? '?'}, '
        'nb_frames=${nbFramesStr ?? '?'}, '
        '실효fps(nb/duration)=${effectiveFps != null ? effectiveFps.toStringAsFixed(2) : '?'}',
      );
    } catch (e) {
      debugPrint('[FrameExtractor] 소스 메타 조회 실패: $e');
    }
  }

  double? _parseFraction(String? value) {
    if (value == null) return null;
    final parts = value.split('/');
    if (parts.length != 2) return null;
    final num = double.tryParse(parts[0]);
    final den = double.tryParse(parts[1]);
    if (num == null || den == null || den == 0) return null;
    return num / den;
  }

  /// 연속 중복 프레임(직전 프레임과 거의 동일한 프레임) 비율을 계측한다.
  /// dup 삽입(원본이 샘플fps 미만일 때 CFR 변환이 시간 보존을 위해 중복을
  /// 끼움)이면 시간축은 정직한 것이고, 중복이 없는데 소스 실효 fps <
  /// 샘플fps면 프레임이 재라벨돼 영상이 빨리 재생되는 것 — 구속이 그
  /// 비율만큼 과대측정된다. 동작에는 영향 없음 — 왜곡 여부 진단 전용.
  void _logDuplicateFrames(List<img.Image> frames) {
    if (frames.length < 2) return;

    var duplicateCount = 0;
    img.Image prevSmall = _shrinkGray(frames.first);
    for (var i = 1; i < frames.length; i++) {
      final small = _shrinkGray(frames[i]);
      if (_avgAbsLumaDiff(prevSmall, small) < _duplicateFrameLumaThreshold) {
        duplicateCount++;
      }
      prevSmall = small;
    }

    final duplicateRatio = duplicateCount / frames.length;
    final estimatedOriginalFps = _sampleFps * (1 - duplicateRatio);
    debugPrint(
      '[FrameExtractor] 연속 중복 프레임: $duplicateCount/${frames.length} '
      '(중복률 ${(duplicateRatio * 100).toStringAsFixed(1)}% '
      '— 원본 실효 fps ≈ ${estimatedOriginalFps.toStringAsFixed(1)})',
    );
  }

  img.Image _shrinkGray(img.Image frame) =>
      img.grayscale(img.copyResize(frame, width: 64));

  double _avgAbsLumaDiff(img.Image a, img.Image b) {
    final total = a.width * a.height;
    if (total == 0) return 0;
    var sum = 0.0;
    for (var y = 0; y < a.height; y++) {
      for (var x = 0; x < a.width; x++) {
        sum += (img.getLuminance(a.getPixel(x, y)) - img.getLuminance(b.getPixel(x, y))).abs();
      }
    }
    return sum / total;
  }
}

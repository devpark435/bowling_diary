import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class FrameExtractionResult {
  final List<img.Image> frames;
  final int originalFps;

  const FrameExtractionResult({
    required this.frames,
    required this.originalFps,
  });
}

class VideoFrameExtractorService {
  static const _sampleFps = 10;

  Future<FrameExtractionResult> extract(String videoPath) async {
    final originalFps = await _getVideoFps(videoPath);

    final tempDir = await getTemporaryDirectory();
    final framesDir = Directory(
      '${tempDir.path}/frames_${DateTime.now().millisecondsSinceEpoch}',
    );
    await framesDir.create();

    try {
      final outputPattern = '${framesDir.path}/frame_%04d.jpg';
      final session = await FFmpegKit.execute(
        '-i "$videoPath" -vf "fps=$_sampleFps,scale=480:-1" -q:v 5 "$outputPattern"',
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

      debugPrint('[FrameExtractor] 추출 완료: ${frames.length}개 프레임, 원본 ${originalFps}fps');
      return FrameExtractionResult(frames: frames, originalFps: originalFps);
    } finally {
      await framesDir.delete(recursive: true);
    }
  }

  /// YOLO person 감지 전용 — 원본 fps로 추출 (320px, 최대 120프레임)
  Future<FrameExtractionResult> extractForPersonDetection(String videoPath) async {
    final originalFps = await _getVideoFps(videoPath);

    final tempDir = await getTemporaryDirectory();
    final framesDir = Directory(
      '${tempDir.path}/person_frames_${DateTime.now().millisecondsSinceEpoch}',
    );
    await framesDir.create();

    try {
      final outputPattern = '${framesDir.path}/frame_%04d.jpg';
      // 원본 fps 유지, 최대 120프레임 (4초 × 30fps)
      final session = await FFmpegKit.execute(
        '-i "$videoPath" -vf "fps=$originalFps,scale=320:-1" -q:v 7 -frames:v 120 "$outputPattern"',
      );
      final returnCode = await session.getReturnCode();
      if (returnCode == null || !returnCode.isValueSuccess()) {
        throw Exception('person 프레임 추출 실패');
      }

      final frameFiles = framesDir.listSync()..sort((a, b) => a.path.compareTo(b.path));
      final frames = <img.Image>[];
      for (final file in frameFiles) {
        if (file is File && file.path.endsWith('.jpg')) {
          final bytes = await file.readAsBytes();
          final image = img.decodeImage(bytes);
          if (image != null) frames.add(image);
        }
      }

      debugPrint('[FrameExtractor] person용 추출 완료: ${frames.length}개 프레임, ${originalFps}fps');
      return FrameExtractionResult(frames: frames, originalFps: originalFps);
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
            final fpsStr = stream.getAverageFrameRate(); // "60/1" 형태
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
}

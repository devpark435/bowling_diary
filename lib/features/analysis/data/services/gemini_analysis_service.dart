import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:bowling_diary/core/constants/app_config.dart';
import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_analysis_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';

List<String> _encodeFrames(List<img.Image> frames) {
  return frames.map((f) => base64Encode(img.encodeJpg(f, quality: 65))).toList();
}

class GeminiAnalysisService {
  static const _baseUrl = 'https://generativelanguage.googleapis.com';
  static const _sampleFps = 10.0;
  static const _maxFrames = 20;

  final _frameExtractor = VideoFrameExtractorService();

  Future<AnalysisData> analyzeVideo(String videoPath, int fps) async {
    final apiKey = AppConfig.geminiApiKey;
    if (apiKey.isEmpty) throw Exception('Gemini API 키 없음');

    // 1. 프레임 추출
    debugPrint('[GeminiAnalysis] 프레임 추출 시작');
    final extracted = await _frameExtractor.extract(videoPath);
    final allFrames = extracted.frames;

    if (allFrames.isEmpty) {
      debugPrint('[GeminiAnalysis] 프레임 추출 실패');
      return AnalysisData(framesAnalyzed: 0, fpsUsed: fps);
    }

    // 최대 프레임 수 제한 (균등 샘플링) — effective fps 계산
    final frames = allFrames.length <= _maxFrames
        ? allFrames
        : _subsample(allFrames, _maxFrames);
    final effectiveFps = _sampleFps * frames.length / allFrames.length;
    final frameIntervalSec = 1.0 / effectiveFps;

    debugPrint('[GeminiAnalysis] ${frames.length}개 프레임 분석 시작 (간격=${frameIntervalSec.toStringAsFixed(3)}s)');

    // 2. 프레임 → JPEG base64 파트 구성 (isolate에서 인코딩)
    final encodedFrames = await compute(_encodeFrames, frames);
    final parts = <Map<String, dynamic>>[];
    for (int i = 0; i < encodedFrames.length; i++) {
      final t = (i * frameIntervalSec).toStringAsFixed(2);
      parts.add({'text': '[프레임 $i | t=${t}s]'});
      parts.add({
        'inline_data': {'mime_type': 'image/jpeg', 'data': encodedFrames[i]},
      });
    }
    parts.add({'text': _buildPrompt(encodedFrames.length, frameIntervalSec)});

    final requestBody = jsonEncode({
      'contents': [{'parts': parts}],
      'generationConfig': {'responseMimeType': 'application/json'},
    });

    // 3. Gemini 요청 (503 시 1회 재시도)
    http.Response res = await http.post(
      Uri.parse('$_baseUrl/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: requestBody,
    ).timeout(const Duration(seconds: 120));

    if (res.statusCode == 503) {
      debugPrint('[GeminiAnalysis] 503 → 3초 후 재시도');
      await Future.delayed(const Duration(seconds: 3));
      res = await http.post(
        Uri.parse('$_baseUrl/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: requestBody,
      ).timeout(const Duration(seconds: 120));
    }

    debugPrint('[GeminiAnalysis] 분석 응답: ${res.statusCode}');

    if (res.statusCode == 429) throw const GeminiQuotaExceededException();
    if (res.statusCode != 200) throw GeminiApiException('API 오류: ${res.statusCode}');

    return _parseResponse(res.body, fps, frames.length, frameIntervalSec);
  }

  List<img.Image> _subsample(List<img.Image> frames, int maxCount) {
    final step = frames.length / maxCount;
    return List.generate(maxCount, (i) => frames[(i * step).round().clamp(0, frames.length - 1)]);
  }

  String _buildPrompt(int frameCount, double intervalSec) => '''
위는 볼링 투구 프레임 시퀀스입니다 (프레임 간격 ${intervalSec.toStringAsFixed(2)}초, 총 $frameCount장, 프레임 번호 0부터 시작).
JSON만 반환하세요.

[분석]
1. "foul_line_frame": 볼링공이 파울라인을 완전히 통과하는 프레임 번호. 불명확 시 null.
2. "arrows_frame": 볼링공이 어프로치 화살표 마크(레인의 삼각형 7개)를 통과하는 프레임 번호. 불명확 시 null.
3. "headpin_frame": 볼링공이 헤드핀(1번 핀)에 처음 닿는 프레임 번호. 불명확 시 null.
4. "rotation_count": 볼 표면 로고·텍스처의 총 회전수 (foul_line_frame ~ 마지막 식별 프레임 기준). 불가 시 null.

{
  "foul_line_frame": null,
  "arrows_frame": null,
  "headpin_frame": null,
  "rotation_count": null
}''';

  AnalysisData _parseResponse(String body, int fps, int frameCount, double frameIntervalSec) {
    try {
      final json = jsonDecode(body);
      final text = json['candidates'][0]['content']['parts'][0]['text'] as String;
      final data = jsonDecode(text) as Map<String, dynamic>;

      final foulLineFrame = data['foul_line_frame'] as int?;
      final arrowsFrame = data['arrows_frame'] as int?;
      final headpinFrame = data['headpin_frame'] as int?;
      final rotationCount = (data['rotation_count'] as num?)?.toDouble();

      debugPrint('[GeminiAnalysis] 프레임 식별: 파울라인=$foulLineFrame, 화살표=$arrowsFrame, 헤드핀=$headpinFrame, 회전수=$rotationCount');

      double? speedKmh;
      int? rpm;

      // 구속 계산 — 우선순위: 파울라인↔헤드핀(18.29m) > 파울라인↔화살표(4.57m) > 화살표↔헤드핀(13.72m)
      int? startFrame, endFrame;
      double? distance;

      if (foulLineFrame != null && headpinFrame != null && headpinFrame > foulLineFrame) {
        startFrame = foulLineFrame; endFrame = headpinFrame; distance = 18.29;
      } else if (foulLineFrame != null && arrowsFrame != null && arrowsFrame > foulLineFrame) {
        startFrame = foulLineFrame; endFrame = arrowsFrame; distance = 4.57;
      } else if (arrowsFrame != null && headpinFrame != null && headpinFrame > arrowsFrame) {
        startFrame = arrowsFrame; endFrame = headpinFrame; distance = 13.72;
      }

      if (startFrame != null && endFrame != null && distance != null) {
        final elapsed = (endFrame - startFrame) * frameIntervalSec;
        final minElapsed = distance / (50.0 / 3.6);
        final maxElapsed = distance / (15.0 / 3.6);

        debugPrint('[GeminiAnalysis] 프레임 $startFrame→$endFrame, elapsed=${elapsed.toStringAsFixed(2)}s, distance=${distance}m');

        if (elapsed >= minElapsed && elapsed <= maxElapsed) {
          speedKmh = double.parse(((distance / elapsed) * 3.6).toStringAsFixed(1));
          debugPrint('[GeminiAnalysis] 구속: $speedKmh km/h');
        } else {
          debugPrint('[GeminiAnalysis] elapsed 비정상(${elapsed.toStringAsFixed(2)}s, 허용: ${minElapsed.toStringAsFixed(2)}~${maxElapsed.toStringAsFixed(2)}s) → 측정불가');
        }

        // RPM 계산
        if (rotationCount != null && rotationCount > 0) {
          final rpmElapsed = (endFrame - startFrame) * frameIntervalSec;
          final rawRpm = (rotationCount / rpmElapsed) * 60;
          if (rawRpm >= 50 && rawRpm <= 500) {
            rpm = rawRpm.round();
            debugPrint('[GeminiAnalysis] RPM: $rpm (회전수=${rotationCount.toStringAsFixed(1)})');
          } else {
            debugPrint('[GeminiAnalysis] RPM 범위 초과(${rawRpm.toStringAsFixed(0)}) → 측정불가');
          }
        }
      } else {
        debugPrint('[GeminiAnalysis] 프레임 식별 실패 → 측정불가');
      }

      debugPrint('[GeminiAnalysis] 결과: ${speedKmh?.toStringAsFixed(1) ?? '측정불가'}km/h, RPM=$rpm');
      return AnalysisData(speedKmh: speedKmh, rpmEstimated: rpm, framesAnalyzed: frameCount, fpsUsed: fps);
    } catch (e) {
      debugPrint('[GeminiAnalysis] 파싱 오류: $e\n$body');
      return AnalysisData(framesAnalyzed: 0, fpsUsed: fps);
    }
  }

  /// 프레임 리스트에서 RPM만 추정 (구속은 로컬 분석 담당)
  Future<int?> analyzeRpm(List<img.Image> allFrames) async {
    final apiKey = AppConfig.geminiApiKey;
    if (apiKey.isEmpty) return null;
    if (allFrames.isEmpty) return null;

    final frames = allFrames.length <= _maxFrames
        ? allFrames
        : _subsample(allFrames, _maxFrames);
    final intervalSec = 1.0 / (_sampleFps * frames.length / allFrames.length);

    final encodedFrames = await compute(_encodeFrames, frames);
    final parts = <Map<String, dynamic>>[];
    for (int i = 0; i < encodedFrames.length; i++) {
      parts.add({'text': '[프레임 $i | t=${(i * intervalSec).toStringAsFixed(2)}s]'});
      parts.add({'inline_data': {'mime_type': 'image/jpeg', 'data': encodedFrames[i]}});
    }
    parts.add({'text': '''
볼링공 프레임 시퀀스입니다 (${intervalSec.toStringAsFixed(2)}초 간격, 총 ${frames.length}장).
볼 표면의 로고·텍스처·광택 패턴 변화를 분석해 분당 회전수(RPM)를 추정하세요.
추정 불가 시 null. JSON만 반환:
{"rpm_estimate": null}'''});

    http.Response res = await http.post(
      Uri.parse('$_baseUrl/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [{'parts': parts}],
        'generationConfig': {'responseMimeType': 'application/json'},
      }),
    ).timeout(const Duration(seconds: 120));

    if (res.statusCode == 503) {
      await Future.delayed(const Duration(seconds: 3));
      res = await http.post(
        Uri.parse('$_baseUrl/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': parts}],
          'generationConfig': {'responseMimeType': 'application/json'},
        }),
      ).timeout(const Duration(seconds: 120));
    }

    if (res.statusCode == 429) throw const GeminiQuotaExceededException();
    if (res.statusCode != 200) throw GeminiApiException('API 오류: ${res.statusCode}');

    try {
      final json = jsonDecode(res.body);
      final text = json['candidates'][0]['content']['parts'][0]['text'] as String;
      final data = jsonDecode(text) as Map<String, dynamic>;
      final rawRpm = (data['rpm_estimate'] as num?)?.toDouble();
      if (rawRpm != null && rawRpm >= 50 && rawRpm <= 500) {
        debugPrint('[GeminiAnalysis] RPM: ${rawRpm.round()}');
        return rawRpm.round();
      }
    } catch (e) {
      debugPrint('[GeminiAnalysis] RPM 파싱 오류: $e');
    }
    return null;
  }

  /// 속도(전체 프레임 랜드마크) + RPM(크롭 볼 이미지) 통합 단일 API 호출
  Future<AnalysisData> analyzeUnified({
    required List<img.Image> frames,
    required List<BallDetection?> ballDetections,
    required int releaseFrame,
    required int sampleFps,
  }) async {
    final apiKey = AppConfig.geminiApiKey;
    if (apiKey.isEmpty) return AnalysisData(framesAnalyzed: frames.length, fpsUsed: sampleFps);
    if (frames.isEmpty) return AnalysisData(framesAnalyzed: 0, fpsUsed: sampleFps);

    const maxFullFrames = 30;
    final fullFrames = frames.length <= maxFullFrames
        ? frames
        : _subsample(frames, maxFullFrames);
    final fullIntervalSec = frames.length / (sampleFps.toDouble() * fullFrames.length);

    const maxCropFrames = 15;
    final cropFrames = _buildCropFrames(frames, ballDetections, releaseFrame, maxCropFrames);
    const cropIntervalSec = 1.0 / 30.0;

    debugPrint('[GeminiAnalysis] 통합 분석: 전체 ${fullFrames.length}장, 크롭 ${cropFrames.length}장');

    final encodedFull = await compute(_encodeFrames, fullFrames);
    final encodedCrops = cropFrames.isNotEmpty ? await compute(_encodeFrames, cropFrames) : <String>[];

    final parts = <Map<String, dynamic>>[];

    parts.add({'text': '[섹션 1: 전체 투구 시퀀스 — ${fullFrames.length}장, 간격 ${fullIntervalSec.toStringAsFixed(3)}s]'});
    for (int i = 0; i < encodedFull.length; i++) {
      parts.add({'text': '[프레임 $i | t=${(i * fullIntervalSec).toStringAsFixed(2)}s]'});
      parts.add({'inline_data': {'mime_type': 'image/jpeg', 'data': encodedFull[i]}});
    }

    if (encodedCrops.isNotEmpty) {
      parts.add({'text': '[섹션 2: 볼링공 크롭 시퀀스 — ${cropFrames.length}장, 30fps 연속]'});
      for (int i = 0; i < encodedCrops.length; i++) {
        parts.add({'text': '[크롭 $i | t=${(i * cropIntervalSec).toStringAsFixed(3)}s]'});
        parts.add({'inline_data': {'mime_type': 'image/jpeg', 'data': encodedCrops[i]}});
      }
    }

    parts.add({'text': _buildUnifiedPrompt(fullFrames.length, fullIntervalSec, cropFrames.length)});

    final requestBody = jsonEncode({
      'contents': [{'parts': parts}],
      'generationConfig': {'responseMimeType': 'application/json'},
    });

    http.Response res = await http.post(
      Uri.parse('$_baseUrl/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: requestBody,
    ).timeout(const Duration(seconds: 120));

    if (res.statusCode == 503) {
      debugPrint('[GeminiAnalysis] 503 → 3초 후 재시도');
      await Future.delayed(const Duration(seconds: 3));
      res = await http.post(
        Uri.parse('$_baseUrl/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: requestBody,
      ).timeout(const Duration(seconds: 120));
    }

    debugPrint('[GeminiAnalysis] 통합 응답: ${res.statusCode}');
    if (res.statusCode == 429) throw const GeminiQuotaExceededException();
    if (res.statusCode != 200) throw GeminiApiException('API 오류: ${res.statusCode}');

    return _parseUnifiedResponse(
      res.body, sampleFps, frames.length,
      fullIntervalSec, cropFrames.length, cropIntervalSec,
    );
  }

  List<img.Image> _buildCropFrames(
    List<img.Image> frames,
    List<BallDetection?> detections,
    int releaseFrame,
    int maxCount,
  ) {
    final crops = <img.Image>[];
    final startIdx = (releaseFrame - 5).clamp(0, frames.length - 1);
    for (int i = startIdx; i < frames.length && crops.length < maxCount; i++) {
      if (i >= detections.length) break;
      final det = detections[i];
      if (det == null) continue;
      final crop = _cropBallForGemini(frames[i], det);
      if (crop != null) crops.add(crop);
    }
    return crops;
  }

  img.Image? _cropBallForGemini(img.Image frame, BallDetection det) {
    final fw = frame.width.toDouble();
    final fh = frame.height.toDouble();
    const pad = 1.5;
    final bw = (det.bw * fw * pad).round();
    final bh = (det.bh * fh * pad).round();
    final x = ((det.cx * fw) - bw / 2).round().clamp(0, frame.width - 1);
    final y = ((det.cy * fh) - bh / 2).round().clamp(0, frame.height - 1);
    final w = bw.clamp(1, frame.width - x);
    final h = bh.clamp(1, frame.height - y);
    if (w < 20 || h < 20) return null;
    final cropped = img.copyCrop(frame, x: x, y: y, width: w, height: h);
    if (cropped.width < 100 || cropped.height < 100) {
      return img.copyResize(cropped, width: 100, height: 100);
    }
    return cropped;
  }

  String _buildUnifiedPrompt(int fullCount, double fullIntervalSec, int cropCount) => '''
위는 볼링 투구 분석 데이터입니다.

섹션 1은 전체 투구 시퀀스($fullCount장, ${fullIntervalSec.toStringAsFixed(3)}초 간격)입니다.
섹션 2는 릴리즈 이후 볼링공 근접 크롭 이미지${cropCount > 0 ? '($cropCount장, 30fps 연속)' : '(없음)'}입니다.

[섹션 1 분석] 다음 프레임 번호를 찾으세요 (불명확하면 null):
- foul_line_frame: 볼이 파울라인(레인 시작 경계선)을 통과하는 프레임 번호
- arrows_frame: 볼이 레인의 삼각형 화살표 마크 7개 위를 통과하는 프레임 번호
- headpin_frame: 볼이 헤드핀(1번 핀)에 처음 접촉하는 프레임 번호

[섹션 2 분석] 크롭 이미지에서 볼 표면(로고·텍스처·광택 반사 패턴) 변화를 추적하세요:
- rotation_count: 첫 크롭~마지막 크롭 사이 볼의 총 회전수 (소수 가능, 예: 2.5회전)

JSON만 반환:
{
  "foul_line_frame": null,
  "arrows_frame": null,
  "headpin_frame": null,
  "rotation_count": null
}''';

  AnalysisData _parseUnifiedResponse(
    String body,
    int sampleFps,
    int totalFrames,
    double fullIntervalSec,
    int cropFrameCount,
    double cropIntervalSec,
  ) {
    try {
      final json = jsonDecode(body);
      final text = json['candidates'][0]['content']['parts'][0]['text'] as String;
      final data = jsonDecode(text) as Map<String, dynamic>;

      final foulLineFrame = data['foul_line_frame'] as int?;
      final arrowsFrame = data['arrows_frame'] as int?;
      final headpinFrame = data['headpin_frame'] as int?;
      final rotationCount = (data['rotation_count'] as num?)?.toDouble();

      debugPrint('[GeminiAnalysis] 식별: 파울라인=$foulLineFrame, 화살표=$arrowsFrame, 헤드핀=$headpinFrame, 회전수=$rotationCount');

      double? speedKmh;
      int? startFrame, endFrame;
      double? distance;

      if (foulLineFrame != null && headpinFrame != null && headpinFrame > foulLineFrame) {
        startFrame = foulLineFrame; endFrame = headpinFrame; distance = 18.29;
      } else if (foulLineFrame != null && arrowsFrame != null && arrowsFrame > foulLineFrame) {
        startFrame = foulLineFrame; endFrame = arrowsFrame; distance = 4.57;
      } else if (arrowsFrame != null && headpinFrame != null && headpinFrame > arrowsFrame) {
        startFrame = arrowsFrame; endFrame = headpinFrame; distance = 13.72;
      }

      if (startFrame != null && endFrame != null && distance != null) {
        final elapsed = (endFrame - startFrame) * fullIntervalSec;
        final minElapsed = distance / (50.0 / 3.6);
        final maxElapsed = distance / (10.0 / 3.6);
        debugPrint('[GeminiAnalysis] 프레임 $startFrame→$endFrame, elapsed=${elapsed.toStringAsFixed(2)}s, distance=${distance}m');
        if (elapsed >= minElapsed && elapsed <= maxElapsed) {
          speedKmh = double.parse(((distance / elapsed) * 3.6).toStringAsFixed(1));
          debugPrint('[GeminiAnalysis] 구속: $speedKmh km/h');
        } else {
          debugPrint('[GeminiAnalysis] elapsed 비정상(${elapsed.toStringAsFixed(2)}s, 허용: ${minElapsed.toStringAsFixed(2)}~${maxElapsed.toStringAsFixed(2)}s) → 측정불가');
        }
      } else {
        debugPrint('[GeminiAnalysis] 랜드마크 식별 실패 → 구속 측정불가');
      }

      int? rpm;
      if (rotationCount != null && rotationCount > 0 && cropFrameCount > 1) {
        final durationSec = (cropFrameCount - 1) * cropIntervalSec;
        final rawRpm = (rotationCount / durationSec) * 60;
        if (rawRpm >= 50 && rawRpm <= 500) {
          rpm = rawRpm.round();
          debugPrint('[GeminiAnalysis] RPM: $rpm (회전수=${rotationCount.toStringAsFixed(1)}, duration=${durationSec.toStringAsFixed(2)}s)');
        } else {
          debugPrint('[GeminiAnalysis] RPM 범위 초과(${rawRpm.toStringAsFixed(0)}) → 측정불가');
        }
      }

      debugPrint('[GeminiAnalysis] 결과: ${speedKmh?.toStringAsFixed(1) ?? '측정불가'}km/h, RPM=$rpm');
      return AnalysisData(speedKmh: speedKmh, rpmEstimated: rpm, framesAnalyzed: totalFrames, fpsUsed: sampleFps);
    } catch (e) {
      debugPrint('[GeminiAnalysis] 파싱 오류: $e\n$body');
      return AnalysisData(framesAnalyzed: totalFrames, fpsUsed: sampleFps);
    }
  }
}

class GeminiQuotaExceededException implements Exception {
  const GeminiQuotaExceededException();
}

class GeminiApiException implements Exception {
  final String message;
  const GeminiApiException(this.message);
  @override
  String toString() => message;
}

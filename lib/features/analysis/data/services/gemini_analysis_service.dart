import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:bowling_diary/core/constants/app_config.dart';
import 'package:bowling_diary/features/analysis/data/services/video_analysis_service.dart';

class GeminiAnalysisService {
  static const _apiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';
  static const _maxFrames = 15;

  Future<AnalysisData> analyze(
    List<img.Image> frames,
    int originalFps, {
    int sampleFps = 10,
  }) async {
    final apiKey = AppConfig.geminiApiKey;
    if (apiKey.isEmpty) throw Exception('Gemini API 키 없음');

    final selected = _selectKeyFrames(frames);
    final intervalMs = (1000 / sampleFps).round();

    debugPrint('[GeminiAnalysis] ${selected.length}개 프레임 전송 (간격 ${intervalMs}ms)');

    final parts = <Map<String, dynamic>>[];
    for (final frame in selected) {
      final jpeg = img.encodeJpg(img.copyResize(frame, width: 640), quality: 75);
      parts.add({
        'inline_data': {
          'mime_type': 'image/jpeg',
          'data': base64Encode(jpeg),
        }
      });
    }
    parts.add({'text': _buildPrompt(selected.length, intervalMs)});

    final response = await http
        .post(
          Uri.parse('$_apiUrl?key=$apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {'parts': parts}
            ],
            'generationConfig': {'responseMimeType': 'application/json'},
          }),
        )
        .timeout(const Duration(seconds: 90));

    debugPrint('[GeminiAnalysis] 응답 코드: ${response.statusCode}');

    if (response.statusCode == 429) throw const GeminiQuotaExceededException();
    if (response.statusCode != 200) {
      throw GeminiApiException('API 오류: ${response.statusCode}');
    }

    return _parseResponse(response.body, selected.length, originalFps);
  }

  List<img.Image> _selectKeyFrames(List<img.Image> frames) {
    if (frames.length <= _maxFrames) return frames;
    final step = frames.length / _maxFrames;
    return List.generate(
      _maxFrames,
      (i) => frames[(i * step).round().clamp(0, frames.length - 1)],
    );
  }

  String _buildPrompt(int frameCount, int intervalMs) => '''
볼링 투구 영상의 연속 프레임 $frameCount장입니다. 프레임 간격은 ${intervalMs}ms입니다.

아래 기준으로 분석해 JSON을 반환하세요.

[속도]
볼링 레인 파울라인~헤드핀 = 18.29m.
볼이 릴리즈된 프레임과 헤드핀 도달 프레임 사이의 경과 시간으로 speed_kmh를 계산하세요.
볼이 보이지 않으면 0.

[RPM]
프레임 간 공 표면 텍스처, 로고, 광택 반사 패턴의 변화량을 분석해 rpm_estimate를 추정하세요.
추정 불가 시 null.

{
  "speed_kmh": 18.5,
  "rpm_estimate": 280
}''';

  AnalysisData _parseResponse(
      String responseBody, int frameCount, int originalFps) {
    try {
      final json = jsonDecode(responseBody);
      final text =
          json['candidates'][0]['content']['parts'][0]['text'] as String;
      final data = jsonDecode(text) as Map<String, dynamic>;

      final speedKmh = (data['speed_kmh'] as num?)?.toDouble() ?? 0.0;
      final rpm = data['rpm_estimate'] as int?;

      debugPrint(
          '[GeminiAnalysis] 결과: ${speedKmh.toStringAsFixed(1)}km/h, RPM=$rpm');

      return AnalysisData(
        speedKmh: double.parse(speedKmh.toStringAsFixed(1)),
        rpmEstimated: rpm,
        framesAnalyzed: frameCount,
        fpsUsed: originalFps,
      );
    } catch (e) {
      debugPrint('[GeminiAnalysis] 파싱 오류: $e');
      return AnalysisData(speedKmh: 0, framesAnalyzed: frameCount, fpsUsed: originalFps);
    }
  }
}

class GeminiQuotaExceededException implements Exception {
  const GeminiQuotaExceededException();
}

class GeminiApiException implements Exception {
  final String message;
  const GeminiApiException(this.message);
}

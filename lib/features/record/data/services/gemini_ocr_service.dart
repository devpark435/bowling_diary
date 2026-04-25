import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:bowling_diary/core/constants/app_config.dart';
import 'package:bowling_diary/features/record/domain/entities/ocr_result.dart';

class GeminiOcrService {
  static const _apiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

  Future<List<OcrPlayerResult>> processImage(String imagePath) async {
    final apiKey = AppConfig.geminiApiKey;
    if (apiKey.isEmpty) throw const GeminiNotConfiguredException();

    debugPrint('[Gemini] 이미지 인식 시작: $imagePath');

    final imageBytes = await File(imagePath).readAsBytes();
    final base64Image = base64Encode(imageBytes);
    final mimeType =
        imagePath.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';

    final response = await http
        .post(
          Uri.parse('$_apiUrl?key=$apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {
                    'inline_data': {
                      'mime_type': mimeType,
                      'data': base64Image,
                    }
                  },
                  {'text': _buildPrompt()},
                ]
              }
            ],
            'generationConfig': {
              'responseMimeType': 'application/json',
            },
          }),
        )
        .timeout(const Duration(seconds: 30));

    debugPrint('[Gemini] 응답 코드: ${response.statusCode}');

    if (response.statusCode == 429) {
      debugPrint('[Gemini] 일일 한도 초과 (429)');
      throw const GeminiQuotaExceededException();
    }
    if (response.statusCode != 200) {
      throw GeminiApiException('API 오류: ${response.statusCode}');
    }

    return _parseResponse(response.body);
  }

  String _buildPrompt() => '''
이 이미지는 볼링 레인의 스코어보드입니다.
각 플레이어의 프레임별 투구 결과를 정확히 추출해주세요.

볼링 점수 표기 규칙:
- 스트라이크: 보타이/깃발/X 모양 아이콘 (firstThrow=10, secondThrow=null, 1~9프레임)
- 스페어: "/" 기호 (firstThrow + secondThrow = 10)
- 미스/거터: "-" 또는 0
- 10프레임: 스트라이크/스페어 시 최대 3투 가능

스코어보드 구조:
- 플레이어당 2행: 위 행=핀 카운트(스트라이크 아이콘 포함), 아래 행=누적 점수(단조 증가, 최대 300)
- 프레임 1~9: 1투+2투, 프레임 10: 1투+2투+(3투)

JSON 배열로만 응답하세요 (설명 없이):
[{"playerName":"이름","frames":[{"frameNumber":1,"firstThrow":10,"secondThrow":null,"thirdThrow":null,"cumulativeScore":30}]}]
''';

  List<OcrPlayerResult> _parseResponse(String responseBody) {
    final outer = jsonDecode(responseBody) as Map<String, dynamic>;
    final text =
        outer['candidates'][0]['content']['parts'][0]['text'] as String;

    debugPrint('[Gemini] 응답 JSON: $text');

    final playersJson = jsonDecode(text) as List<dynamic>;

    return playersJson.map((p) {
      final playerMap = p as Map<String, dynamic>;
      final framesJson = playerMap['frames'] as List<dynamic>;

      final frames = framesJson.map((f) {
        final fm = f as Map<String, dynamic>;
        final frameNum = fm['frameNumber'] as int;
        final first = fm['firstThrow'] as int?;
        final second = fm['secondThrow'] as int?;

        final isStrike = first == 10 && frameNum < 10;
        final isSpare = !isStrike &&
            first != null &&
            second != null &&
            first + second == 10;

        return OcrFrameResult(
          frameNumber: frameNum,
          firstThrow: first,
          secondThrow: second,
          thirdThrow: fm['thirdThrow'] as int?,
          cumulativeScore: fm['cumulativeScore'] as int?,
          confidence: OcrConfidence.high,
          isStrike: isStrike,
          isSpare: isSpare,
        );
      }).toList();

      return OcrPlayerResult(
        playerName: (playerMap['playerName'] as String?) ?? '플레이어',
        frames: frames,
      );
    }).toList();
  }
}

class GeminiQuotaExceededException implements Exception {
  const GeminiQuotaExceededException();
  @override
  String toString() => 'GeminiQuotaExceededException: 일일 API 한도 초과';
}

class GeminiNotConfiguredException implements Exception {
  const GeminiNotConfiguredException();
  @override
  String toString() => 'GeminiNotConfiguredException: API 키 미설정';
}

class GeminiApiException implements Exception {
  final String message;
  const GeminiApiException(this.message);
  @override
  String toString() => 'GeminiApiException: $message';
}

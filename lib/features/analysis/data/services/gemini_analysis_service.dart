import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:bowling_diary/core/constants/app_config.dart';
import 'package:bowling_diary/features/analysis/data/services/video_analysis_service.dart';

class GeminiAnalysisService {
  static const _baseUrl = 'https://generativelanguage.googleapis.com';

  /// 영상 파일을 Gemini File API로 업로드 후 분석
  Future<AnalysisData> analyzeVideo(String videoPath, int fps) async {
    final apiKey = AppConfig.geminiApiKey;
    if (apiKey.isEmpty) throw Exception('Gemini API 키 없음');

    final file = File(videoPath);
    final fileSize = await file.length();
    final mimeType = videoPath.toLowerCase().endsWith('.mov')
        ? 'video/quicktime'
        : 'video/mp4';

    debugPrint('[GeminiAnalysis] 영상 업로드 시작: ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB');

    String? fileUri;
    String? fileName;

    try {
      // 1. 업로드
      final uploadResult = await _uploadVideo(file, fileSize, mimeType, apiKey);
      fileUri = uploadResult.$1;
      fileName = uploadResult.$2;

      // 2. 처리 완료 대기
      await _waitForProcessing(fileName, apiKey);

      // 3. 분석 요청
      return await _requestAnalysis(fileUri, mimeType, fps, apiKey);
    } on GeminiQuotaExceededException {
      rethrow;
    } catch (e) {
      throw GeminiApiException(e.toString());
    } finally {
      // 4. 업로드된 파일 삭제 (용량 절약)
      if (fileName != null) {
        await _deleteFile(fileName, apiKey);
      }
    }
  }

  /// 리주머블 업로드 → (fileUri, fileName) 반환
  Future<(String, String)> _uploadVideo(
    File file,
    int fileSize,
    String mimeType,
    String apiKey,
  ) async {
    // Step 1: 업로드 세션 시작
    final initRes = await http.post(
      Uri.parse('$_baseUrl/upload/v1beta/files?key=$apiKey'),
      headers: {
        'X-Goog-Upload-Protocol': 'resumable',
        'X-Goog-Upload-Command': 'start',
        'X-Goog-Upload-Header-Content-Length': fileSize.toString(),
        'X-Goog-Upload-Header-Content-Type': mimeType,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'file': {'display_name': 'bowling_video'}}),
    );

    final uploadUrl = initRes.headers['x-goog-upload-url'];
    if (uploadUrl == null) {
      throw Exception('업로드 URL 없음 (${initRes.statusCode})');
    }

    // Step 2: 파일 업로드
    final bytes = await file.readAsBytes();
    final uploadRes = await http.post(
      Uri.parse(uploadUrl),
      headers: {
        'Content-Length': fileSize.toString(),
        'X-Goog-Upload-Offset': '0',
        'X-Goog-Upload-Command': 'upload, finalize',
        'Content-Type': mimeType,
      },
      body: bytes,
    ).timeout(const Duration(minutes: 3));

    if (uploadRes.statusCode != 200) {
      throw Exception('업로드 실패: ${uploadRes.statusCode}');
    }

    final data = jsonDecode(uploadRes.body);
    final fileUri = data['file']['uri'] as String;
    final fileName = data['file']['name'] as String;
    debugPrint('[GeminiAnalysis] 업로드 완료: $fileName');
    return (fileUri, fileName);
  }

  /// 파일 처리 상태가 ACTIVE 될 때까지 폴링
  Future<void> _waitForProcessing(String fileName, String apiKey) async {
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(seconds: 3));
      final res = await http.get(
        Uri.parse('$_baseUrl/v1beta/$fileName?key=$apiKey'),
      );
      final state = jsonDecode(res.body)['state'] as String?;
      debugPrint('[GeminiAnalysis] 처리 상태: $state');
      if (state == 'ACTIVE') return;
      if (state == 'FAILED') throw Exception('Gemini 영상 처리 실패');
    }
    throw Exception('영상 처리 시간 초과');
  }

  /// 분석 요청 → AnalysisData 반환
  Future<AnalysisData> _requestAnalysis(
    String fileUri,
    String mimeType,
    int fps,
    String apiKey,
  ) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'file_data': {'mime_type': mimeType, 'file_uri': fileUri}},
              {'text': _buildPrompt()},
            ]
          }
        ],
        'generationConfig': {'responseMimeType': 'application/json'},
      }),
    ).timeout(const Duration(seconds: 90));

    debugPrint('[GeminiAnalysis] 분석 응답: ${res.statusCode}');

    if (res.statusCode == 429) throw const GeminiQuotaExceededException();
    if (res.statusCode != 200) throw GeminiApiException('API 오류: ${res.statusCode}');

    return _parseResponse(res.body, fps);
  }

  Future<void> _deleteFile(String fileName, String apiKey) async {
    try {
      await http.delete(
        Uri.parse('$_baseUrl/v1beta/$fileName?key=$apiKey'),
      );
      debugPrint('[GeminiAnalysis] 파일 삭제 완료');
    } catch (_) {}
  }

  String _buildPrompt() => '''
볼링 투구 분석 전문가로서 영상의 정확한 타임스탬프를 추출하세요. JSON으로만 응답하세요.

1. "start_time": 공이 투구자의 손에서 떨어져 파울 라인을 통과하는 시점 (초 단위, 식별 불가 시 null)
2. "end_time": 공이 1번 핀에 충돌하는 시점 (초 단위, 식별 불가 시 null)
3. "rotation_count": 공이 start_time~end_time 동안 로고나 문양이 몇 바퀴 회전하는지 관찰 (추정 불가 시 null)

반환 형식:
{
  "start_time": null,
  "end_time": null,
  "rotation_count": null
}''';

  AnalysisData _parseResponse(String body, int fps) {
    try {
      final json = jsonDecode(body);
      final text = json['candidates'][0]['content']['parts'][0]['text'] as String;
      final data = jsonDecode(text) as Map<String, dynamic>;

      final startTime = (data['start_time'] as num?)?.toDouble();
      final endTime = (data['end_time'] as num?)?.toDouble();
      final rotationCount = (data['rotation_count'] as num?)?.toDouble();

      double? speedKmh;
      int? rpm;

      if (startTime != null && endTime != null) {
        final elapsed = endTime - startTime;
        debugPrint('[GeminiAnalysis] start=${startTime}s end=${endTime}s elapsed=${elapsed.toStringAsFixed(3)}s');

        if (elapsed > 0) {
          // 구속 계산
          final rawSpeed = (18.288 / elapsed) * 3.6;
          if (rawSpeed >= 15 && rawSpeed <= 50) {
            speedKmh = double.parse(rawSpeed.toStringAsFixed(1));
            debugPrint('[GeminiAnalysis] 구속: ${speedKmh}km/h');
          } else {
            debugPrint('[GeminiAnalysis] 구속 범위 초과(${rawSpeed.toStringAsFixed(1)}km/h) → 측정불가');
          }

          // RPM 계산
          if (rotationCount != null && rotationCount > 0) {
            final rawRpm = (rotationCount / elapsed) * 60;
            if (rawRpm >= 50 && rawRpm <= 500) {
              rpm = rawRpm.round();
              debugPrint('[GeminiAnalysis] RPM: $rpm (회전수=${rotationCount.toStringAsFixed(1)})');
            } else {
              debugPrint('[GeminiAnalysis] RPM 범위 초과(${rawRpm.toStringAsFixed(0)}) → 측정불가');
            }
          }
        } else {
          debugPrint('[GeminiAnalysis] elapsed 비정상(${elapsed.toStringAsFixed(3)}s) → 측정불가');
        }
      } else {
        debugPrint('[GeminiAnalysis] 타임스탬프 null → 측정불가');
      }

      debugPrint('[GeminiAnalysis] 결과: ${speedKmh?.toStringAsFixed(1) ?? '측정불가'}km/h, RPM=$rpm');

      return AnalysisData(
        speedKmh: speedKmh,
        rpmEstimated: rpm,
        framesAnalyzed: 0,
        fpsUsed: fps,
      );
    } catch (e) {
      debugPrint('[GeminiAnalysis] 파싱 오류: $e\n$body');
      return AnalysisData(framesAnalyzed: 0, fpsUsed: fps);
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

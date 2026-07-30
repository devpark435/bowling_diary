import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bowling_diary/core/services/debug_log_buffer.dart';

/// 분석 1회의 진단 결과를 Supabase `analysis_debug_logs`에 한 행으로 남긴다.
///
/// 목적 두 가지:
/// 1. TestFlight 실패 원인 추적 — 콘솔이 없어 `debugPrint`가 전부 사라진다.
/// 2. 구속 표본 축적 — 랜드마크/기존 두 코어 값을 매 투구마다 모아야
///    "20km/h가 맞나(스피드건 25)"를 표본 1개가 아닌 분포로 판단할 수 있다.
///
/// 내부 QA 전용 — 공개 배포 전 테이블과 함께 제거.
class AnalysisDebugLogService {
  AnalysisDebugLogService({SupabaseClient? client, DebugLogBuffer? buffer})
      : _client = client ?? Supabase.instance.client,
        _buffer = buffer ?? DebugLogBuffer.instance;

  final SupabaseClient _client;
  final DebugLogBuffer _buffer;

  static const String tableName = 'analysis_debug_logs';

  /// 업로드 실패가 분석 흐름을 절대 깨지 않도록 모든 예외를 삼킨다 —
  /// 진단 수집은 부가 기능이고, 여기서 던지면 원인 진단 자체가 불가능해진다.
  Future<void> log({
    required String outcome,
    String? stage,
    Object? error,
    StackTrace? stack,
    Map<String, dynamic>? metrics,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[AnalysisDebugLog] 미로그인 — 업로드 생략');
        return;
      }
      await _client.from(tableName).insert(<String, dynamic>{
        'user_id': userId,
        'app_version': await _appVersion(),
        'device': _device(),
        'outcome': outcome,
        'stage': stage,
        'error': error?.toString(),
        'stack': stack?.toString(),
        'logs': _buffer.dump(),
        'metrics': metrics,
      });
      debugPrint('[AnalysisDebugLog] 업로드 완료 ($outcome)');
    } catch (e) {
      debugPrint('[AnalysisDebugLog] 업로드 실패(무시): $e');
    }
  }

  Future<String?> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (e) {
      return null;
    }
  }

  String? _device() {
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (e) {
      return null;
    }
  }
}

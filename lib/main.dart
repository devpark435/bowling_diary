import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowling_diary/app/app.dart' show AppRestarter, preloadTheme;
import 'package:bowling_diary/core/constants/supabase_constants.dart';
import 'package:bowling_diary/core/services/debug_log_buffer.dart';

void main() async {
  // 분석 진단 로그를 서버로 올릴 수 있게 debugPrint를 버퍼에 적재한다
  // (내부 QA 전용 — 공개 배포 전 제거).
  DebugLogBuffer.install();

  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await initializeDateFormatting('ko');

  await Supabase.initialize(
    url: SupabaseConstants.url,
    anonKey: SupabaseConstants.anonKey,
  );

  await preloadTheme(); // 첫 프레임 전에 팔레트 세팅
  FlutterNativeSplash.remove();

  runApp(const AppRestarter());
}

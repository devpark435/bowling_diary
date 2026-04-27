import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowling_diary/app/app.dart' show AppRestarter, preloadTheme;
import 'package:bowling_diary/core/constants/supabase_constants.dart';

void main() async {
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

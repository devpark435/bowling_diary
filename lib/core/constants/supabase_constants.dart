class SupabaseConstants {
  SupabaseConstants._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'YOUR_SUPABASE_URL',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'YOUR_SUPABASE_ANON_KEY',
  );

  static const String ballImagesBucket = 'ball-images';
  static const String ballCatalogBucket = 'ball-catalog';
  static const String sessionPhotosBucket = 'session-photos';
  static const String profileImagesBucket = 'profile-images';

  /// 회원탈퇴 시 Auth 사용자 삭제용 Edge Function 이름 (supabase/README.md 배포 가이드)
  static const String deleteAccountEdgeFunction = 'delete-account';
}

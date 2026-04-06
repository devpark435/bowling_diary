import 'package:flutter/material.dart';
import 'package:new_version_plus/new_version_plus.dart';

class AppUpdateService {
  AppUpdateService._();

  static bool _hasChecked = false;

  static Future<void> checkForUpdate(BuildContext context) async {
    if (_hasChecked) return;
    _hasChecked = true;

    try {
      final newVersion = NewVersionPlus(
        androidId: 'com.devpark.bowling_diary',
        iOSId: 'com.devpark.bowlingDiary',
      );

      final status = await newVersion.getVersionStatus();
      if (status == null || !context.mounted) return;

      if (status.canUpdate) {
        if (!context.mounted) return;
        newVersion.showUpdateDialog(
          context: context,
          versionStatus: status,
          dialogTitle: '새 버전이 있어요!',
          dialogText: '더 나은 볼링 기록을 위해 업데이트해주세요.\n\n'
              '현재 버전: ${status.localVersion}\n'
              '최신 버전: ${status.storeVersion}',
          updateButtonText: '업데이트',
          dismissButtonText: '나중에',
        );
      }
    } catch (_) {
      // 앱스토어 미등록 상태 등에서는 무시
    }
  }
}

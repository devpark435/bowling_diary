import 'package:flutter/services.dart';

class NativeYuvConverter {
  static const _channel = MethodChannel('bowling_diary/yuv_converter');

  /// CameraImage YUV420 데이터 → RGBA8888 변환.
  /// 반환: width * height * 4 바이트 (R, G, B, A 순).
  /// 회전 보정은 호출자 책임 (Phase 5.1에서 처리).
  static Future<Uint8List> convert({
    required int width,
    required int height,
    required Uint8List yPlane,
    required Uint8List uPlane,
    required Uint8List vPlane,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
  }) async {
    final result = await _channel.invokeMethod<Map>('convert', {
      'width': width,
      'height': height,
      'yPlane': yPlane,
      'uPlane': uPlane,
      'vPlane': vPlane,
      'yRowStride': yRowStride,
      'uvRowStride': uvRowStride,
      'uvPixelStride': uvPixelStride,
    });
    if (result == null) {
      throw StateError('YuvConverter 응답 누락');
    }
    return result['rgba'] as Uint8List;
  }
}

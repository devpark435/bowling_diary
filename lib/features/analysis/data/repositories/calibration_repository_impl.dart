import 'dart:convert';

import 'package:bowling_diary/features/analysis/domain/entities/calibration_profile.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:bowling_diary/features/analysis/domain/repositories/calibration_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 캘리브레이션 프로파일 저장소 구현체 (SharedPreferences 기반)
///
/// - 프로파일 목록: `calibration_profiles_v1` 키에 JSON 배열로 저장
/// - 기본 프로파일 id: `calibration_default_id_v1` 키에 문자열로 저장
///
/// JSON 형식:
/// ```json
/// {
///   "id": "...",
///   "name": "...",
///   "viewpoint": "sideRight",
///   "homography": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
///   "createdAt": "2026-01-01T00:00:00.000"
/// }
/// ```
class CalibrationRepositoryImpl implements CalibrationRepository {
  static const _profilesKey = 'calibration_profiles_v1';
  static const _defaultIdKey = 'calibration_default_id_v1';

  final SharedPreferences _prefs;

  CalibrationRepositoryImpl(this._prefs);

  // ──────────────────────────── 내부 직렬화 ────────────────────────────

  /// [CalibrationProfile]을 JSON Map으로 변환한다.
  Map<String, dynamic> _toJson(CalibrationProfile profile) {
    return {
      'id': profile.id,
      'name': profile.name,
      'viewpoint': profile.viewpoint.name,
      'homography': profile.homography.toRowMajorList(),
      'createdAt': profile.createdAt.toIso8601String(),
    };
  }

  /// JSON Map을 [CalibrationProfile]로 변환한다.
  CalibrationProfile _fromJson(Map<String, dynamic> json) {
    final viewpoint = CameraViewpoint.values.firstWhere(
      (e) => e.name == json['viewpoint'] as String,
    );
    final homographyValues =
        (json['homography'] as List<dynamic>).map((e) => (e as num).toDouble()).toList();
    final homography = HomographyMatrix.fromRowMajor(homographyValues);
    return CalibrationProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      viewpoint: viewpoint,
      homography: homography,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// 저장된 프로파일 목록을 JSON 문자열로부터 읽어 반환한다.
  List<Map<String, dynamic>> _readRawList() {
    final raw = _prefs.getString(_profilesKey);
    if (raw == null) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }

  /// 프로파일 목록을 JSON 문자열로 저장한다.
  Future<void> _writeRawList(List<Map<String, dynamic>> list) async {
    await _prefs.setString(_profilesKey, jsonEncode(list));
  }

  // ──────────────────────────── public API ────────────────────────────

  @override
  Future<List<CalibrationProfile>> listAll() async {
    return _readRawList().map(_fromJson).toList();
  }

  @override
  Future<CalibrationProfile?> getById(String id) async {
    final list = _readRawList();
    final json = list.cast<Map<String, dynamic>?>().firstWhere(
      (e) => e!['id'] == id,
      orElse: () => null,
    );
    return json != null ? _fromJson(json) : null;
  }

  @override
  Future<void> save(CalibrationProfile profile) async {
    final list = _readRawList();
    final idx = list.indexWhere((e) => e['id'] == profile.id);
    final json = _toJson(profile);
    if (idx >= 0) {
      // 동일 id 존재 → 덮어쓰기 (upsert)
      list[idx] = json;
    } else {
      list.add(json);
    }
    await _writeRawList(list);
  }

  @override
  Future<void> delete(String id) async {
    final list = _readRawList();
    list.removeWhere((e) => e['id'] == id);
    await _writeRawList(list);

    // 삭제된 프로파일이 기본값이면 기본값도 제거
    final defaultId = _prefs.getString(_defaultIdKey);
    if (defaultId == id) {
      await _prefs.remove(_defaultIdKey);
    }
  }

  @override
  Future<CalibrationProfile?> getDefault() async {
    final defaultId = _prefs.getString(_defaultIdKey);
    if (defaultId == null) return null;
    return getById(defaultId);
  }

  @override
  Future<void> setDefault(String id) async {
    await _prefs.setString(_defaultIdKey, id);
  }
}

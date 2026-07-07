import 'dart:convert';
import 'package:bowling_diary/features/analysis/domain/entities/calibration_profile.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:bowling_diary/features/analysis/domain/repositories/calibration_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CalibrationRepositoryImpl implements CalibrationRepository {
  static const _profilesKey = 'calibration_profiles_v1';
  static const _defaultIdKey = 'calibration_default_id_v1';
  final SharedPreferences _prefs;
  CalibrationRepositoryImpl(this._prefs);

  Map<String, dynamic> _framePointToJson(FramePoint p) => {'nx': p.nx, 'ny': p.ny};

  FramePoint _framePointFromJson(Map<String, dynamic> json) => FramePoint(
        nx: (json['nx'] as num).toDouble(),
        ny: (json['ny'] as num).toDouble(),
      );

  Map<String, dynamic> _toJson(CalibrationProfile profile) => {
        'id': profile.id,
        'name': profile.name,
        'viewpoint': profile.viewpoint.name,
        'homography': profile.homography.toRowMajorList(),
        'createdAt': profile.createdAt.toIso8601String(),
        'referenceImagePath': profile.referenceImagePath,
        'framePoints': profile.framePoints.map(_framePointToJson).toList(),
      };

  CalibrationProfile _fromJson(Map<String, dynamic> json) {
    final viewpoint = CameraViewpoint.values.firstWhere(
      (e) => e.name == json['viewpoint'] as String,
      orElse: () => throw FormatException('알 수 없는 viewpoint: ${json['viewpoint']}'),
    );
    final homographyValues =
        (json['homography'] as List<dynamic>).map((e) => (e as num).toDouble()).toList();
    final homography = HomographyMatrix.fromRowMajor(homographyValues);
    final framePoints = (json['framePoints'] as List<dynamic>)
        .map((e) => _framePointFromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return CalibrationProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      viewpoint: viewpoint,
      homography: homography,
      createdAt: DateTime.parse(json['createdAt'] as String),
      referenceImagePath: json['referenceImagePath'] as String,
      framePoints: framePoints,
    );
  }

  List<Map<String, dynamic>> _readRawList() {
    final raw = _prefs.getString(_profilesKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeRawList(List<Map<String, dynamic>> list) async {
    await _prefs.setString(_profilesKey, jsonEncode(list));
  }

  @override
  Future<List<CalibrationProfile>> listAll() async {
    final result = <CalibrationProfile>[];
    for (final json in _readRawList()) {
      try {
        result.add(_fromJson(json));
      } catch (e) {
        debugPrint('[CalibrationRepository] 프로파일 디코딩 실패 (id=${json['id']}): $e');
      }
    }
    return result;
  }

  @override
  Future<CalibrationProfile?> getById(String id) async {
    final list = _readRawList();
    for (final json in list) {
      if (json['id'] == id) return _fromJson(json);
    }
    return null;
  }

  @override
  Future<void> save(CalibrationProfile profile) async {
    final list = _readRawList();
    final idx = list.indexWhere((e) => e['id'] == profile.id);
    final json = _toJson(profile);
    if (idx >= 0) {
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
    final defaultId = _prefs.getString(_defaultIdKey);
    if (defaultId == id) await _prefs.remove(_defaultIdKey);
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

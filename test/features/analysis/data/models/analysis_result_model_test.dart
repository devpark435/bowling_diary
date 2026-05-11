import 'package:bowling_diary/features/analysis/data/models/analysis_result_model.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toJson/fromJson 라운드트립 (trajectory 포함)', () {
    final model = AnalysisResultModel(
      id: 'a',
      userId: 'u',
      recordedAt: DateTime.parse('2026-05-11T10:00:00.000Z'),
      speedKmh: 25.5,
      rpmEstimated: 350,
      fpsUsed: 30,
      videoLocalPath: '/tmp/x.mp4',
      createdAt: DateTime.parse('2026-05-11T10:00:01.000Z'),
      releasePosM: const LanePoint(xM: 0.5, yM: 0.0),
      breakPosM: const LanePoint(xM: 0.55, yM: 12.0),
      aimAngleDeg: 2.3,
      trajectoryLane: const [
        LanePoint(xM: 0.5, yM: 0.0),
        LanePoint(xM: 0.52, yM: 5.0),
        LanePoint(xM: 0.55, yM: 12.0),
        LanePoint(xM: 0.6, yM: 18.0),
      ],
    );

    final json = model.toJson();
    expect(json['release_pos_m'], {'xM': 0.5, 'yM': 0.0});
    expect((json['trajectory_lane'] as List).length, 4);

    // 시뮬레이트: Supabase에서 받은 row에 추가 필드 포함
    final rebuilt = AnalysisResultModel.fromJson({
      ...json,
      'recorded_at': '2026-05-11T10:00:00.000Z',
      'created_at': '2026-05-11T10:00:01.000Z',
    });
    expect(rebuilt.releasePosM?.xM, 0.5);
    expect(rebuilt.trajectoryLane.length, 4);
    expect(rebuilt.aimAngleDeg, 2.3);
  });

  test('새 필드 없는 row도 디코딩 가능 (backward compat)', () {
    final json = {
      'id': 'a',
      'user_id': 'u',
      'recorded_at': '2026-05-11T10:00:00.000Z',
      'speed_kmh': 25.5,
      'rpm_estimated': 350,
      'fps_used': 30,
      'created_at': '2026-05-11T10:00:01.000Z',
    };
    final model = AnalysisResultModel.fromJson(json);
    expect(model.releasePosM, isNull);
    expect(model.breakPosM, isNull);
    expect(model.aimAngleDeg, isNull);
    expect(model.trajectoryLane, isEmpty);
  });
}

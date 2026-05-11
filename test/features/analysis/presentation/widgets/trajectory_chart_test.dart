import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/trajectory_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('빈 trajectory도 렌더링 가능', (tester) async {
    await tester.pumpWidget(wrap(const TrajectoryChart(trajectory: [])));
    expect(find.byType(TrajectoryChart), findsOneWidget);
  });

  testWidgets('단일 점 trajectory 렌더링', (tester) async {
    await tester.pumpWidget(wrap(
      const TrajectoryChart(trajectory: [LanePoint(xM: 0.5, yM: 0.0)]),
    ));
    expect(find.byType(TrajectoryChart), findsOneWidget);
  });

  testWidgets('전체 trajectory + break + release 렌더링', (tester) async {
    final traj = List.generate(
      10,
      (i) => LanePoint(xM: 0.5 + i * 0.01, yM: i * 1.8),
    );
    await tester.pumpWidget(wrap(TrajectoryChart(
      trajectory: traj,
      releasePos: const LanePoint(xM: 0.5, yM: 0),
      breakPos: const LanePoint(xM: 0.55, yM: 12),
    )));
    expect(find.byType(TrajectoryChart), findsOneWidget);
  });
}

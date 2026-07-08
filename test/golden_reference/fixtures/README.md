# 골든 레퍼런스 fixture

각 fixture는 다음 3개 파일로 구성:
- `<name>.mp4`: 트리밍된 투구 영상
- `<name>.calibration.json`: 해당 촬영 위치의 CalibrationProfile JSON (CalibrationRepositoryImpl._toJson 포맷)
- `<name>.expected.json`: `{"groundTruthKmh": <구속계 실측값>, "toleranceKmh": <허용오차>}`

이 디렉토리는 기본적으로 비어있다. 실제 투구 영상 fixture를 추가해야 speed_regression_test.dart가 회귀 비교를 실행한다.

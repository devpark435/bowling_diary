# 볼링다이어리 🎳

볼링 점수를 스마트하게 기록하고 투구를 분석하는 iOS 앱

---

## 주요 기능

### 스코어 기록
스코어보드를 촬영하면 OCR이 자동으로 점수를 인식해 기록합니다.

<!-- TODO: 스크린샷 추가 -->
<!-- ![스코어 기록](docs/screenshots/score_record.png) -->

### 투구 분석 `BETA`
갤러리에서 투구 영상을 선택하면 구속과 RPM을 자동 분석합니다.

- **구속 (km/h)**: Gemini Vision이 레인 랜드마크(파울라인, 화살표, 헤드핀)를 식별해 계산
- **RPM**: 볼 표면 텍스처 패턴 변화 추적

> 카메라 앵글과 조명 조건에 따라 정확도가 달라질 수 있습니다.

<!-- TODO: 스크린샷 추가 -->
<!-- ![투구 분석](docs/screenshots/analysis.png) -->

### 통계 & 히스토리
게임 기록을 바탕으로 개인 볼링 데이터를 관리하고 통계를 확인합니다.

<!-- TODO: 스크린샷 추가 -->
<!-- ![통계](docs/screenshots/stats.png) -->

### 볼 관리
보유 중인 볼링공을 등록하고 카탈로그에서 정보를 검색할 수 있습니다.

<!-- TODO: 스크린샷 추가 -->
<!-- ![볼 관리](docs/screenshots/balls.png) -->

---

## 기술 스택

| 분류 | 기술 |
|------|------|
| Framework | Flutter (iOS) |
| 상태 관리 | Riverpod |
| 라우팅 | GoRouter |
| 백엔드 | Supabase |
| OCR | Google ML Kit (Korean) |
| 영상 분석 | YOLOv8n TFLite + Gemini 2.5 Flash Vision |
| 영상 처리 | FFmpeg Kit |

---

## 아키텍처

Clean Architecture 기반 — `domain / data / presentation` 레이어 분리

```
lib/
├── app/           # 라우터, 테마
├── core/          # 공통 유틸, 상수
└── features/
    ├── record/    # 스코어 기록 (OCR)
    ├── analysis/  # 투구 분석
    ├── balls/     # 볼 관리
    └── auth/      # 인증
```

---

## 설치 및 실행

### 요구사항
- Flutter 3.x 이상
- Xcode (iOS 빌드)
- Supabase 프로젝트
- Gemini API 키

### 환경 변수 설정

```bash
flutter run \
  --dart-define=SUPABASE_URL=your_url \
  --dart-define=SUPABASE_ANON_KEY=your_key \
  --dart-define=GEMINI_API_KEY=your_key
```

### 실행

```bash
flutter pub get
flutter run
```

---

## 볼링 도메인

### 스코어보드 구조
- 플레이어당 2행: **핀 카운트 행** + **누적 점수 행**
- 프레임 1~9: 투구 2개 / 프레임 10: 투구 최대 3개

### 점수 표기

| 표기 | 의미 |
|------|------|
| 볼/깃발 아이콘 | 스트라이크 |
| `/` | 스페어 |
| `-` | 거터/미스 |
| 숫자 | 쓰러뜨린 핀 수 |

---

## 라이선스

MIT

# beacon_app

ESP32 BLE 비콘 기반 동아리 출석 체크 Flutter 앱 (Android / iOS).

## 실행

```bash
cp .env.example .env   # API_BASE_URL 확인
flutter pub get
flutter run
```

## 구조

| 경로 | 역할 |
|---|---|
| `lib/core/` | 설정, 네트워크, 저장소, 라우터, 테마 |
| `lib/components/ui/` | 코드베이스가 소유하는 UI 프리미티브 |
| `lib/features/` | 기능 단위 (data / presentation) |

## 연관 리포

- 펌웨어: [beacon_esp32](https://github.com/Dev-MAMOKEY/beacon_esp32)
- 웹 대시보드: [beacon_frontend](https://github.com/Dev-MAMOKEY/beacon_frontend)

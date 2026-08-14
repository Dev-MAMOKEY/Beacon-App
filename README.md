# beacon_app

ESP32 BLE 비콘 기반 동아리 출석 체크 Flutter 앱 (Android / iOS).

## 실행

```bash
cp .env.example .env   # API_BASE_URL 확인
flutter pub get
flutter run
```

## 백엔드 호스트

`API_BASE_URL`은 `.env`에만 있고 어떤 git 추적 파일에도 남기지 않는다
(`.env.example`은 키만 담고 값은 비워둔다). Android는 `android/app/build.gradle.kts`의
Gradle 태스크가 `.env`의 호스트를 읽어 `network_security_config.template.xml`로부터
`network_security_config.xml`을 빌드 시점에 생성한다(`preBuild`에 연결되어 리소스
병합 전에 항상 실행됨). 생성된 파일은 `.gitignore` 대상이라 커밋되지 않는다.

iOS는 아직 이 저장소에서 빌드하지 않는다(CocoaPods 미설치, 오너 결정). iOS를 처음
빌드하게 되면 호스트를 `Info.plist`에 하드코딩하지 말고, Android와 같은 원칙으로
ATS 예외(`NSAppTransportSecurity`)를 빌드 시점에 주입하도록 만들어야 한다.

## 구조

| 경로 | 역할 |
|---|---|
| `lib/core/` | 설정, 네트워크, 저장소, 라우터, 테마 |
| `lib/components/ui/` | 코드베이스가 소유하는 UI 프리미티브 |
| `lib/features/` | 기능 단위 (data / presentation) |

## 연관 리포

- 펌웨어: [beacon_esp32](https://github.com/Dev-MAMOKEY/beacon_esp32)
- 웹 대시보드: [beacon_frontend](https://github.com/Dev-MAMOKEY/beacon_frontend)

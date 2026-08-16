import java.io.FileInputStream
import java.net.URI
import java.net.URISyntaxException
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 릴리즈 서명 정보. `android/key.properties`는 .gitignore 대상이라 각자 로컬에
// 만들어 쓴다(양식은 `android/key.properties.example`). 파일이 없으면 null이고,
// 그 경우 릴리즈 빌드는 디버그 키로 서명된다 — 배포하면 안 되는 산출물이다.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties: Properties? =
    if (keystorePropertiesFile.exists()) {
        val loaded = Properties()
        FileInputStream(keystorePropertiesFile).use { stream -> loaded.load(stream) }
        loaded
    } else {
        null
    }

// 백엔드 호스트는 어떤 git 추적 파일에도 남기지 않는다. 저장소 루트의 .env가
// 갖고 있는 API_BASE_URL에서 호스트만 뽑아 network_security_config.template.xml에
// 채워 network_security_config.xml을 만든다 — 이 파일 자체는 .gitignore 대상이다.
// preBuild가 이 태스크에 의존하므로 리소스 병합 전에 항상 최신 상태로 갱신된다.
val generateNetworkSecurityConfig by tasks.registering {
    group = "build setup"
    description = "저장소 루트 .env의 API_BASE_URL 호스트로 network_security_config.xml을 생성한다."

    val envFile = rootProject.projectDir.parentFile.resolve(".env")
    // res/xml/ 아래 모든 파일은 Android 리소스 컴파일러가 리소스로 취급하고
    // 파일명에 점(.)이 두 개 이상 있으면 빌드를 깨뜨리므로, 템플릿은 리소스
    // 디렉터리 밖(app 모듈 루트)에 둔다.
    val templateFile = file("network_security_config.template.xml")
    val outputFile = file("src/main/res/xml/network_security_config.xml")

    // .env는 없을 수도 있는 입력이다. inputs.file()로 선언하면 Gradle이 태스크
    // 실행 전에 "파일이 존재해야 한다"고 자체 검증해 버려서, 우리가 던지려는
    // 안내 메시지 대신 Gradle의 일반 검증 에러가 뜬다 — 그래서 파일이 아니라
    // 내용(부재 시 "MISSING")을 값으로 취급하는 property로 추적한다. 부재
    // 여부·형식 판단은 doLast에서 직접 하고 우리 메시지로 실패시킨다.
    inputs.property("envFileContents") { if (envFile.exists()) envFile.readText() else "MISSING" }
    inputs.file(templateFile)
    outputs.file(outputFile)

    doLast {
        if (!envFile.exists()) {
            throw GradleException(
                "${envFile.absolutePath} 가 없습니다. 저장소 루트에서 " +
                    "`cp .env.example .env` 실행 후 API_BASE_URL 값을 채워주세요."
            )
        }

        val apiBaseUrlLine = envFile.readLines()
            .map { it.trim() }
            .firstOrNull { it.startsWith("API_BASE_URL=") }
            ?: throw GradleException(
                "${envFile.absolutePath} 에 API_BASE_URL이 없습니다. " +
                    "`cp .env.example .env` 후 API_BASE_URL 값을 채워주세요."
            )

        val rawValue = apiBaseUrlLine.substringAfter("API_BASE_URL=").trim()

        val host = try {
            URI(rawValue).host
        } catch (e: URISyntaxException) {
            null
        }

        if (host.isNullOrBlank()) {
            throw GradleException(
                "${envFile.absolutePath} 의 API_BASE_URL 값에서 호스트를 읽을 수 " +
                    "없습니다. `cp .env.example .env` 후 올바른 URL(예: " +
                    "http://호스트:포트)로 채워주세요."
            )
        }

        outputFile.writeText(templateFile.readText().replace("__API_HOST__", host))
    }
}

android {
    namespace = "com.mamokey.beacon"
    // flutter_secure_storage 11.x가 compileSdk 37을 요구함 (Flutter 기본값은 36). flutter.compileSdkVersion으로 되돌리면 빌드가 다시 깨짐.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mamokey.beacon"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // `android/key.properties`가 있을 때만 릴리즈 서명 설정을 만든다.
        // 그 파일과 키스토어(.jks/.keystore)는 .gitignore 대상이다 — 서명 키가
        // git에 들어가면 저장소를 보는 누구나 이 앱 이름으로 서명된 APK를
        // 만들 수 있고, 리포는 public이다.
        if (keystoreProperties != null) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // key.properties가 있으면 그 키로, 없으면 디버그 키로 서명한다.
            //
            // **디버그 키로 서명된 APK는 절대 배포하면 안 된다.** Android는
            // 앱의 서명 신원을 영구 고정하므로, 디버그 키로 한 번 올리면
            // 나중에 프로덕션 키로 업데이트를 올릴 수 없다(같은 키를 요구한다).
            // 그래서 배포용 빌드는 반드시 key.properties가 있는 상태에서 해야
            // 하고, 아래 경고가 그 사실을 빌드 로그에 남긴다.
            //
            // 그럼에도 디버그 폴백을 유지하는 이유: 키 없이도
            // `flutter run --release`로 성능·크기를 확인할 수 있어야 한다.
            signingConfig = if (keystoreProperties != null) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "⚠️  android/key.properties가 없어 릴리즈 빌드를 디버그 키로 서명합니다. " +
                        "이 APK는 배포용이 아닙니다 — android/key.properties.example을 참고하세요."
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// 모든 변형(variant)의 리소스 병합보다 먼저 실행되도록 preBuild에 건다.
tasks.named("preBuild") {
    dependsOn(generateNetworkSecurityConfig)
}

flutter {
    source = "../.."
}

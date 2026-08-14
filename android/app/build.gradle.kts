import java.net.URI
import java.net.URISyntaxException

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

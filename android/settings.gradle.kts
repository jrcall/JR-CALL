// ===============================================================
// JR CALL
// File: settings.gradle.kts
// Location: android/settings.gradle.kts
//
// PRODUCTION ANDROID / FLUTTER SETTINGS
//
// CONTRACT:
// - Flutter 3.44.x compatible.
// - Android Gradle Plugin 9.0.1 retained deliberately.
// - Gradle 9.1.x compatibility preserved.
// - JDK 17 compatibility preserved.
// - Legacy Kotlin compatibility retained for Flutter 3.44.
// - Flutter Gradle plugin loader preserved.
// - Google / Maven Central / Gradle Plugin Portal preserved.
// - Firebase Google Services plugin preserved.
// - Firebase package/configuration identity untouched.
// - No Auth / OTP / Profile / Search logic changed.
// - No Call Engine / WebRTC / signaling logic changed.
//
// IMPORTANT:
// - AGP 9.2.x is intentionally NOT adopted at this checkpoint.
// - AGP 9.2.x requires Gradle 9.4.1.
// - The current project is already aligned with AGP 9.0.1 +
//   Gradle 9.1.x.
// - AndroidGradlePluginVersion suppression below is IDE/Lint-only.
// - It does not alter Gradle execution or application runtime.
// ===============================================================

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()

            file("local.properties").inputStream().use { input ->
                properties.load(input)
            }

            val sdkPath = properties.getProperty("flutter.sdk")

            require(!sdkPath.isNullOrBlank()) {
                "flutter.sdk not set in local.properties"
            }

            sdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    // ===========================================================
    // FLUTTER
    // ===========================================================

    id("dev.flutter.flutter-plugin-loader") version "1.0.0"

    // ===========================================================
    // ANDROID GRADLE PLUGIN
    //
    // AGP 9.0.1 is intentionally retained because it matches the
    // project's current Gradle 9.1.x / JDK 17 configuration.
    //
    // Android Lint may advertise a newer AGP release. Upgrading
    // that major build component independently would also require
    // a compatible Gradle wrapper migration and another complete
    // compatibility audit.
    //
    // Therefore only the official Android Lint inspection for
    // this deliberate version pin is suppressed.
    // ===========================================================

    //noinspection AndroidGradlePluginVersion
    id("com.android.application") version "9.0.1" apply false

    // ===========================================================
    // FIREBASE / GOOGLE SERVICES
    //
    // Processes android/app/google-services.json.
    // ===========================================================

    id("com.google.gms.google-services") version "4.5.0" apply false

    // ===========================================================
    // KOTLIN
    //
    // Flutter 3.44 provides temporary compatibility for projects
    // and plugins still using the legacy Kotlin Gradle Plugin
    // while AGP 9 migration is in progress.
    //
    // org.jetbrains.kotlin.android is intentionally NOT declared
    // here because this application module does not require a new
    // independent Kotlin plugin declaration at this checkpoint.
    //
    // Built-in Kotlin migration must only be performed when the
    // application and every dependent Flutter plugin have been
    // verified compatible together.
    // ===========================================================
}

include(":app")

// ===============================================================
// END OF FILE
// Location: android/settings.gradle.kts
//
// PRESERVED:
//
// ✓ Flutter plugin loader
// ✓ AGP 9.0.1
// ✓ Gradle 9.1.x compatibility
// ✓ JDK 17 compatibility
// ✓ Google repository
// ✓ Maven Central
// ✓ Gradle Plugin Portal
// ✓ Firebase Google Services 4.5.0
//
// IDE / LINT:
//
// ✓ AndroidGradlePluginVersion warning suppressed officially
// ✓ AGP runtime version unchanged
// ✓ No fake dependency version
// ✓ No forced AGP 9.2.x migration
//
// UNTOUCHED:
//
// ✓ applicationId / package identity
// ✓ google-services.json
// ✓ SHA-1 / SHA-256
// ✓ Firebase Auth
// ✓ Phone OTP
// ✓ Email OTP
// ✓ App Check
// ✓ Firestore / Storage
// ✓ Profile / Search
// ✓ Call Engine
// ✓ Message Engine
// ✓ WebRTC / Signaling
// ✓ Flutter UI / design
// ===============================================================
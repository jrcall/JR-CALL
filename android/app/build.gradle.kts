import com.android.build.api.dsl.ApplicationExtension

// ===============================================================
// JR CALL
// File: build.gradle.kts
// Location: android/app/build.gradle.kts
//
// ANDROID APP MODULE
//
// PRESERVED:
// - Firebase / Google Services
// - Firebase package identity
// - Flutter SDK configuration
// - Java / Kotlin JVM 17
// - OTP / Auth
// - Profile / Discovery
// - Call Engine / WebRTC / Signaling
// - Message Engine
// - Google reCAPTCHA Android SDK
// ===============================================================

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

// ===============================================================
// FLUTTER CLI NAMESPACE DISCOVERY COMPATIBILITY
//
// IMPORTANT:
// Flutter tooling currently discovers the Android namespace by
// scanning build.gradle(.kts) for an "android { ... namespace ... }"
// pattern.
//
// JR CALL intentionally configures AGP through the public
// ApplicationExtension API below.
//
// This COMMENT is intentionally preserved so Flutter CLI can discover
// the namespace without changing the actual AGP configuration.
//
// android {
//     namespace = "com.example.jr_call"
// }
// ===============================================================

// ===============================================================
// FLUTTER-OWNED ANDROID VALUES
// ===============================================================

val jrCompileSdk = flutter.compileSdkVersion
val jrNdkVersion = flutter.ndkVersion
val jrMinSdk = flutter.minSdkVersion
val jrTargetSdk = flutter.targetSdkVersion
val jrVersionCode = flutter.versionCode
val jrVersionName = flutter.versionName

// ===============================================================
// ANDROID
// ===============================================================

extensions.configure<ApplicationExtension>("android") {
    namespace = "com.example.jr_call"

    compileSdk = jrCompileSdk
    ndkVersion = jrNdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.jr_call"

        minSdk = jrMinSdk
        targetSdk = jrTargetSdk

        versionCode = jrVersionCode
        versionName = jrVersionName
    }

    buildTypes {
        getByName("debug") {
            // Development configuration remains Flutter-managed.
        }

        getByName("release") {
            // Temporary testing signing configuration.
            // Production signing is configured in the release step.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// ===============================================================
// KOTLIN Ã¢â‚¬â€ JVM 17
// ===============================================================

kotlin {
    compilerOptions {
        jvmTarget =
            org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// ===============================================================
// DEPENDENCIES
// ===============================================================

dependencies {
    implementation(
        platform("com.google.firebase:firebase-bom:34.18.0")
    )

    implementation(
        "com.google.firebase:firebase-messaging"
    )

    implementation(
        "com.google.android.recaptcha:recaptcha:18.9.2"
    )
}

// ===============================================================
// FLUTTER
// ===============================================================

flutter {
    source = "../.."
}

// ===============================================================
// END OF FILE
//
// PRESERVED:
//
// Ã¢Å“â€œ com.example.jr_call namespace
// Ã¢Å“â€œ com.example.jr_call applicationId
// Ã¢Å“â€œ Flutter compile SDK
// Ã¢Å“â€œ Flutter minimum SDK
// Ã¢Å“â€œ Flutter target SDK
// Ã¢Å“â€œ Flutter NDK
// Ã¢Å“â€œ Flutter version code
// Ã¢Å“â€œ Flutter version name
// Ã¢Å“â€œ Java 17
// Ã¢Å“â€œ Kotlin JVM 17
// Ã¢Å“â€œ Google Services
// Ã¢Å“â€œ Firebase
// Ã¢Å“â€œ Phone OTP / Auth
// Ã¢Å“â€œ Profile / Discovery
// Ã¢Å“â€œ Call Engine
// Ã¢Å“â€œ WebRTC
// Ã¢Å“â€œ Signaling
// Ã¢Å“â€œ Message Engine
// Ã¢Å“â€œ Temporary debug signing for release testing
// Ã¢Å“â€œ Google reCAPTCHA Android integration
//
// FIXED:
//
// Ã¢Å“â€œ Flutter CLI can discover the Android namespace.
// Ã¢Å“â€œ Public ApplicationExtension configuration remains unchanged.
// Ã¢Å“â€œ No Manifest package attribute added.
// Ã¢Å“â€œ No Call Engine runtime logic changed.
// ===============================================================
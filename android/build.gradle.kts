// ===============================================================
// JR CALL
// File: build.gradle.kts
// Location: android/build.gradle.kts
//
// ROOT ANDROID BUILD CONFIGURATION
//
// CONTRACT:
// - Compatible with current Kotlin DSL structure.
// - Compatible with AGP 9 built-in Kotlin migration.
// - Keeps Google + Maven Central repositories.
// - Preserves Flutter shared build directory structure.
// - Does not touch Firebase/Auth/Profile/Search/OTP logic.
// - Does not touch Call Engine/WebRTC/signaling.
// ===============================================================

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// ===============================================================
// SHARED FLUTTER BUILD DIRECTORY
// ===============================================================

val newBuildDir =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()

rootProject.layout.buildDirectory.value(newBuildDir)

// ===============================================================
// SUBPROJECT BUILD DIRECTORIES
// ===============================================================

subprojects {
    val newSubprojectBuildDir =
        newBuildDir.dir(project.name)

    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// ===============================================================
// APP EVALUATION ORDER
// ===============================================================

subprojects {
    project.evaluationDependsOn(":app")
}

// ===============================================================
// CLEAN
// ===============================================================

tasks.register<Delete>("clean") {
    group = "build"
    description = "Deletes the JR CALL project build directory."

    delete(rootProject.layout.buildDirectory)
}

// ===============================================================
// END OF FILE
// File: android/build.gradle.kts
//
// STATUS:
// - AGP 9 structure compatible
// - Kotlin DSL compatible
// - No deprecated setBuildDir()
// - Call Engine untouched
// - Firebase/Profile/Search/OTP untouched
//
// NEXT FILE: android/app/build.gradle.kts
// ===============================================================
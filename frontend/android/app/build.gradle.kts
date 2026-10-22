plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.school365ai.app"
    // flutter_secure_storage 11 requires 37, and Flutter still defaults to
    // 36. Pinned here with android.suppressUnsupportedCompileSdk in
    // gradle.properties (docs/driver-app.md, D0).
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent: Play identifies the app by this for ever, and it
        // cannot be changed after the first upload (docs/driver-app.md).
        applicationId = "com.school365ai.app"
        // Pinned rather than taken from Flutter's defaults, which move with
        // the SDK. A bus driver's phone is old and cheap, so the floor is a
        // deliberate choice: 24 covers Android 7, which is as far back as
        // the plugins here reach.
        minSdk = 24
        // What the app is tested against and declares to the OS. Separate
        // from compileSdk above, which only decides which APIs compile.
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
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

flutter {
    source = "../.."
}

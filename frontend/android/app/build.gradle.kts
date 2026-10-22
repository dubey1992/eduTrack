import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The Google Maps key for Android.
//
// The web app asks the server for its key, so it can be rotated without a
// release (docs/maps.md). The Android SDK cannot work that way: it reads
// the key from the manifest when the process starts, long before anything
// has asked the server anything. So it is a build-time value, and it lives
// in android/local.properties - which git ignores, so no key is ever
// committed. A build without one still works; every map degrades to the
// list screens, exactly as it does on the web with no key.
val mapsApiKey: String = run {
    val properties = Properties()
    val file = rootProject.file("local.properties")

    if (file.exists()) {
        file.inputStream().use { properties.load(it) }
    }

    properties.getProperty("MAPS_API_KEY") ?: ""
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

        // Read by the manifest's com.google.android.geo.API_KEY meta-data.
        manifestPlaceholders["mapsApiKey"] = mapsApiKey
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

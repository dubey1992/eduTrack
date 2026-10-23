import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload key. Kept out of the repo entirely: android/key.properties
// names a keystore that lives outside the project, and .gitignore ignores
// both the properties file and any .jks that wanders in.
//
// A machine without it still builds - CI, a new laptop, anybody checking
// out the repo - the release just falls back to the debug key and cannot
// be uploaded to Play. That is better than a build that fails with a
// missing-file error nobody can act on (docs/driver-app.md, D1.2).
val signing: java.util.Properties? = run {
    val file = rootProject.file("key.properties")

    if (!file.exists()) {
        null
    } else {
        Properties().also { properties -> file.inputStream().use { properties.load(it) } }
    }
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
    // flutter_secure_storage 11 compiles against 37 and Flutter still
    // defaults to 36, so the app has to meet it or the AAR metadata check
    // refuses the build. It needs AGP 9.3+ to resolve: earlier versions
    // looked for a platform directory named android-37, which the SDK
    // manager publishes as android-37.0 (docs/driver-app.md, D1.4).
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // The Navigation SDK uses java.time, which Android 7 does not have.
        // Required for any minSdk below 34 (docs/driver-app.md, D7).
        isCoreLibraryDesugaringEnabled = true
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

    signingConfigs {
        if (signing != null) {
            create("upload") {
                storeFile = file(signing.getProperty("storeFile"))
                storePassword = signing.getProperty("storePassword")
                keyAlias = signing.getProperty("keyAlias")
                keyPassword = signing.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // The upload key where this machine has it, the debug key where
            // it does not - so a release build always runs, and only a
            // properly signed one can reach Play.
            signingConfig = if (signing != null) {
                signingConfigs.getByName("upload")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// The Navigation SDK *contains* the Maps SDK rather than depending on it,
// so a build carrying both google_maps_flutter and the Navigation SDK fails
// with several hundred "Duplicate class com.google.android.gms.maps..."
// errors. Google's own answer is to drop the standalone Maps library and
// let the navigation artifact provide those classes (docs/driver-app.md).
configurations.all {
    exclude(group = "com.google.android.gms", module = "play-services-maps")
}

dependencies {
    // The _nio flavour, not the plain one: the Navigation SDK uses
    // java.nio.file, and AGP refuses the build without it.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs_nio:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.hastveda.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.hastveda.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            // TODO: Before submitting to Google Play, replace these with your actual keystore values.
            // Run: keytool -genkey -v -keystore hastveda-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias hastveda
            // Then set these values (or use environment variables / key.properties file):
            storeFile = file(System.getenv("KEYSTORE_PATH") ?: "debug.keystore")
            storePassword = System.getenv("KEYSTORE_PASSWORD") ?: "android"
            keyAlias = System.getenv("KEY_ALIAS") ?: "androiddebugkey"
            keyPassword = System.getenv("KEY_PASSWORD") ?: "android"
        }
    }

    buildTypes {
        release {
            // Use release signing config when env vars are set, otherwise fall back to debug
            signingConfig = if (System.getenv("KEYSTORE_PATH") != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

// ── HastVeda launcher icon generation ────────────────────────────────────────
// Runs `dart run flutter_launcher_icons` before every Android build so the
// HastVeda logo PNG is generated into all mipmap-* density folders.
// This is required because the Rocket APK pipeline does not execute the tool
// automatically; wiring it here as a Gradle preBuild dependency ensures it
// always runs before `flutter build apk`.
tasks.register<Exec>("generateLauncherIcons") {
    description = "Generates HastVeda launcher icon PNGs into mipmap-* folders"
    group = "build"
    workingDir = file("../..")
    commandLine("dart", "run", "flutter_launcher_icons")
    // Do not fail the build if the tool is unavailable in the pipeline environment;
    // the static mipmap resources already checked in will be used as fallback.
    isIgnoreExitValue = true
}

// Disabled to prevent duplicate resource conflicts with colors.xml
// afterEvaluate {
//     tasks.matching { it.name == "preBuild" }.configureEach {
//         dependsOn("generateLauncherIcons")
//     }
// }
// ─────────────────────────────────────────────────────────────────────────────

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.multidex:multidex:2.0.1")
    implementation("com.google.android.material:material:1.13.0")
    implementation("androidx.concurrent:concurrent-futures:1.3.0")
    implementation("com.getkeepsafe.relinker:relinker:1.4.5")
}

import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing, in order of preference:
//   1. android/key.properties (local builds; git-ignored) with storeFile, storePassword,
//      keyAlias and keyPassword;
//   2. the environment (CI: the Android release workflow sets ANDROID_KEYSTORE_PATH,
//      ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD from the
//      ANDROID_KEYSTORE_* secrets);
//   3. neither: the debug key, so a sideloadable APK always builds.
// Only a fixed key lets the in-app updater install a newer release over an older one.
val keyProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
// A relative storeFile resolves against android/app, as in Flutter's signing guide.
val releaseStore: File? = (keyProperties.getProperty("storeFile") ?: System.getenv("ANDROID_KEYSTORE_PATH"))
    ?.let { file(it) }
    ?.takeIf { it.exists() }

android {
    namespace = "com.lightwave.openmtg.app"
    // permission_handler_android needs API 37; Flutter's default is 36.
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    // path_provider's jni dependency compiles C with this NDK; CI caches it (see
    // .github/workflows/android-release.yml) because the download arrives corrupt now and then.
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time and needs desugaring.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.lightwave.openmtg.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml; CI passes --build-number (its run number).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseStore != null) {
                storeFile = releaseStore
                storePassword = keyProperties.getProperty("storePassword") ?: System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = keyProperties.getProperty("keyAlias") ?: System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = keyProperties.getProperty("keyPassword") ?: System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseStore != null) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.core:core-ktx:1.15.0") // FileProvider for the in-app updater
}

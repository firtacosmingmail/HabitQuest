import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Compose compiler: the home-screen widgets are written with Jetpack Glance.
    id("org.jetbrains.kotlin.plugin.compose")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Release signing (Google Play upload key)
//
// Read from, in this order:
//   1. android/key.properties (gitignored):
//        storeFile=<path to the .jks; relative paths are relative to android/app/>
//        storePassword=<keystore password>
//        keyAlias=<key alias>
//        keyPassword=<key password>
//   2. Environment variables (CI can set these instead of writing the file):
//        ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_PASSWORD,
//        ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD
//
// With neither, release builds fall back to the debug key (android/app/
// debug.keystore) so local release builds need no secrets. Set
// ANDROID_REQUIRE_RELEASE_SIGNING=true (the release workflow does) to fail
// the build instead of falling back. Nothing secret lives in this file;
// key.properties, *.jks and *.keystore (except app/debug.keystore) are
// gitignored in android/.gitignore.
// ---------------------------------------------------------------------------
class ReleaseSigning(
    val storeFile: File,
    val storePassword: String,
    val keyAlias: String,
    val keyPassword: String,
)

val releaseSigning: ReleaseSigning? = run {
    // key.properties key -> environment variable
    val envNames = mapOf(
        "storeFile" to "ANDROID_KEYSTORE_PATH",
        "storePassword" to "ANDROID_KEYSTORE_PASSWORD",
        "keyAlias" to "ANDROID_KEY_ALIAS",
        "keyPassword" to "ANDROID_KEY_PASSWORD",
    )
    val keys = envNames.keys.toList()
    val propsFile = rootProject.file("key.properties")
    val values: Map<String, String?>
    val source: String
    val missing: List<String>
    if (propsFile.exists()) {
        val props = Properties()
        propsFile.inputStream().use { props.load(it) }
        values = keys.associateWith { props.getProperty(it)?.trim() }
        source = "android/key.properties"
        missing = keys.filter { values[it].isNullOrBlank() }
    } else {
        values = keys.associateWith { System.getenv(envNames.getValue(it)) }
        source = "environment variables"
        missing = keys.filter { values[it].isNullOrBlank() }.map { envNames.getValue(it) }
    }
    when {
        missing.isEmpty() -> {
            val store = file(values.getValue("storeFile")!!)
            if (!store.exists()) {
                throw GradleException("Release keystore $store (from $source) does not exist")
            }
            ReleaseSigning(
                storeFile = store,
                storePassword = values.getValue("storePassword")!!,
                keyAlias = values.getValue("keyAlias")!!,
                keyPassword = values.getValue("keyPassword")!!,
            )
        }
        // A half-configured key is a mistake, not a request for the fallback.
        missing.size < keys.size ->
            throw GradleException("Release signing from $source is missing: ${missing.joinToString()}")
        System.getenv("ANDROID_REQUIRE_RELEASE_SIGNING") == "true" ->
            throw GradleException(
                "ANDROID_REQUIRE_RELEASE_SIGNING=true but no release key is configured " +
                    "(android/key.properties or ANDROID_KEYSTORE_* env vars)",
            )
        else -> null
    }
}

android {
    namespace = "com.vvs.habitquest"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (java.time on older Android).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        // Jetpack Glance home-screen widgets (com.vvs.habitquest.widgets).
        compose = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.vvs.habitquest"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // google_mobile_ads 9.x needs at least API 24.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        // Shared debug key committed to the repo (standard debug credentials) so
        // every machine produces the SHA-1 registered for Google sign-in.
        // Debug-only: never use this for a store release.
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        // Play upload key, only when one is configured (see releaseSigning above).
        if (releaseSigning != null) {
            create("release") {
                storeFile = releaseSigning.storeFile
                storePassword = releaseSigning.storePassword
                keyAlias = releaseSigning.keyAlias
                keyPassword = releaseSigning.keyPassword
            }
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            // With an upload key: signed for Google Play. Without one: the debug
            // key, so a local `flutter build apk --release` / `flutter run
            // --release` still works (such builds cannot be uploaded to Play).
            signingConfig = if (releaseSigning != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Home-screen widgets. home_widget already exposes glance-appwidget as an
    // `api` dependency; it is declared here too so the app does not depend on
    // the plugin's transitive graph. Keep it in step with home_widget's version.
    implementation("androidx.glance:glance-appwidget:1.2.0")
    // Background daily refresh of the widgets (widgets/WidgetRefresh.kt).
    // Not a new library in the APK: home_widget 0.10 already ships it (as an
    // `implementation` dependency, so it is not on our compile classpath) for
    // its background callback. Keep it at home_widget's version.
    implementation("androidx.work:work-runtime-ktx:2.11.2")
}

import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load release signing material from android/keystore.properties when it
// exists. The file is gitignored; see keystore.properties.example for the
// expected keys. Falls back to debug signing if the file is absent so
// `flutter run --debug` keeps working for contributors who haven't
// provisioned a keystore.
val keystorePropertiesFile = rootProject.file("keystore.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}

android {
    namespace = "com.dsdogs.nousmind"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time APIs that aren't
        // available on older Android API levels; enable desugaring so
        // those calls get rewritten against desugar_jdk_libs at build time.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.dsdogs.nousmind"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                // storeFile is relative to android/app/ (the module dir),
                // matching the layout described in keystore.properties.example.
                storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
            // Sign with both v1 (JAR) and v2 (APK Signature Scheme). v1 keeps
            // legacy tools like `keytool -printcert -jarfile` and
            // `jarsigner -verify` working; v2 is what the Play Store and modern
            // installers verify and is required for distribution.
            enableV1Signing = true
            enableV2Signing = true
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // No keystore provisioned — keep building with debug keys
                // so `flutter run --release` still works for local testing.
                // Production builds require android/keystore.properties.
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    dependencies {
        coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
        // Bundled Chinese text recognition: the model ships inside
        // the AAR, so the app does not need Google Play Services to
        // download anything at runtime. The 16.0.x line is a
        // self-contained library — the previous comment about
        // NoClassDefFoundError described the older v1 unbundled
        // artifact, not this one.
        implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
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

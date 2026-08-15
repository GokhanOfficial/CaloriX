import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release imzalama — `android/key.properties` mevcutsa okunur (Play
// Console upload keystore'u). Yoksa (yerel debug / CI) debug anahtarına
// düşer; build pipeline'ı kırılmaz. key.properties gitignore'da.
val keystoreProperties = Properties().apply {
    val keystoreFile = rootProject.file("key.properties")
    if (keystoreFile.exists()) {
        load(FileInputStream(keystoreFile))
    }
}

android {
    namespace = "com.calorix.calorix"
    // file_picker 8.x en az compileSdk 36 bekliyor (flutter.compileSdkVersion=34).
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications için gerekli
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.calorix.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.containsKey("keyAlias")) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // key.properties varsa release keystore ile, yoksa debug anahtarıyla
            // imzala (CI build pipeline'ı yeşil kalsın diye). Play Console'a
            // yüklenen AAB gerçek upload keystore'u ile imzalanmalı.
            signingConfig = if (keystoreProperties.containsKey("keyAlias")) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // R8: minify + resource shrinking. keep kuralları
            // proguard-rules.pro'da (model/supabase/riverpod koruması).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // camera_android_camerax'in eksik transitif bağımlılığı (CameraX 1.5.x jspecify derleme hatası)
    // https://github.com/flutter/flutter/issues/ — camera plugin known issue
    implementation("androidx.concurrent:concurrent-futures:1.2.0")
}

flutter {
    source = "../.."
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "cc.huevia"
    compileSdk = flutter.compileSdkVersion
    // Existing native libraries are consumed without rebuilding or changing them.

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cc.huevia.next"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = 35
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures { buildConfig = true }
    sourceSets.getByName("main") {
        java.srcDirs("../../../../app/src/main/java", "../../../core/java")
        res.srcDir("../../../../app/src/main/res")
        assets.srcDir("../../../../app/src/main/assets")
        jniLibs.srcDir("../../../../app/src/main/jniLibs")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    implementation(files("../../../../app/libs/litert-1.4.1.jar", "../../../../app/libs/litert-api-1.4.1.jar", "../../../../app/libs/open_sdk_3.5.19_r9483ffc7_lite.jar"))
    compileOnly(files("../../../../app/libs/compile-only/support-fragment-28.0.0.jar"))
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

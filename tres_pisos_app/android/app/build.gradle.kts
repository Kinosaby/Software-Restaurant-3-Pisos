plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.trespisos.tres_pisos_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.trespisos.tres_pisos_app"
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

    // Firma permanente: la aportan las variables POS_* (en CI, desde los secretos
    // ANDROID_*). Sin ellas se firma con la clave de debug, que sirve para probar
    // pero no permite actualizar encima de un APK firmado con otra clave.
    val releaseStore = System.getenv("POS_KEYSTORE_PATH")
    val releaseAlias = System.getenv("POS_KEY_ALIAS")
    val releaseStorePassword = System.getenv("POS_STORE_PASSWORD")
    val releaseKeyPassword = System.getenv("POS_KEY_PASSWORD")
    val firmaPermanente = listOf(releaseStore, releaseAlias, releaseStorePassword, releaseKeyPassword)
        .all { !it.isNullOrBlank() }

    signingConfigs {
        if (firmaPermanente) {
            create("release") {
                storeFile = file(releaseStore!!)
                keyAlias = releaseAlias
                storePassword = releaseStorePassword
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (firmaPermanente) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("Sin POS_KEYSTORE_PATH/POS_KEY_ALIAS/POS_STORE_PASSWORD/POS_KEY_PASSWORD: release firmado con la clave de debug.")
                signingConfigs.getByName("debug")
            }
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

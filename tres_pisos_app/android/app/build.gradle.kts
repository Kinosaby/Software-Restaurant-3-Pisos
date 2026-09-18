plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseStore = System.getenv("POS_KEYSTORE_PATH")
val releaseAlias = System.getenv("POS_KEY_ALIAS")
val releaseStorePassword = System.getenv("POS_STORE_PASSWORD")
val releaseKeyPassword = System.getenv("POS_KEY_PASSWORD")
val hasReleaseKey = listOf(releaseStore, releaseAlias, releaseStorePassword, releaseKeyPassword)
    .all { !it.isNullOrBlank() }
val allowTestSigning = System.getenv("POS_ALLOW_TEST_SIGNING") == "true"

android {
    namespace = "com.trespisos.tres_pisos_app"
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
        applicationId = "com.kinosaby.trespisos"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("production") {
                storeFile = file(releaseStore!!)
                storePassword = releaseStorePassword
                keyAlias = releaseAlias
                keyPassword = releaseKeyPassword
            }
        }
    }
    buildTypes {
        release {
            signingConfig = when {
                hasReleaseKey -> signingConfigs.getByName("production")
                allowTestSigning -> signingConfigs.getByName("debug")
                else -> null
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

val requireReleaseKey = tasks.register("requireReleaseKey") {
    doLast {
        check(hasReleaseKey || allowTestSigning) {
            "Configura POS_KEYSTORE_PATH, POS_KEY_ALIAS, POS_STORE_PASSWORD y POS_KEY_PASSWORD. " +
                "Solo para validación se permite POS_ALLOW_TEST_SIGNING=true."
        }
    }
}
tasks.configureEach {
    if (name == "preReleaseBuild") dependsOn(requireReleaseKey)
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "tn.biobalance.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // BIOBALANCE_APP_ID_SUFFIX / BIOBALANCE_APP_LABEL let one phone hold several copies (one per test account).
        applicationId = "tn.biobalance.app" + (System.getenv("BIOBALANCE_APP_ID_SUFFIX") ?: "")
        manifestPlaceholders["appLabel"] = System.getenv("BIOBALANCE_APP_LABEL") ?: "BioBalance"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release builds are signed with a key that never lives in the repository:
    // BIOBALANCE_KEYSTORE, BIOBALANCE_KEYSTORE_PASSWORD, BIOBALANCE_KEY_ALIAS, BIOBALANCE_KEY_PASSWORD.
    val keystorePath = System.getenv("BIOBALANCE_KEYSTORE")
    signingConfigs {
        if (keystorePath != null) {
            create("production") {
                storeFile = file(keystorePath)
                storePassword = System.getenv("BIOBALANCE_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("BIOBALANCE_KEY_ALIAS")
                keyPassword = System.getenv("BIOBALANCE_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            if (keystorePath != null) signingConfig = signingConfigs.getByName("production")
        }
    }
}

// A release must be signed: refuse to produce an unsigned one by accident.
gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any {
        it.project.path == project.path && it.name.contains("release", ignoreCase = true)
    }
    if (buildsRelease) {
        require(System.getenv("BIOBALANCE_KEYSTORE") != null) {
            "Release signing is required: set BIOBALANCE_KEYSTORE and the related variables."
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

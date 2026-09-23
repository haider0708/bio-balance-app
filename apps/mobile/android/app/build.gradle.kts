import java.util.Base64

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
        val defines = (project.findProperty("dart-defines") as? String).orEmpty()
            .split(",").filter { it.isNotEmpty() }
            .map { String(Base64.getDecoder().decode(it)) }
        // Independent private installations share code and signing, never permissions.
        val installation = defines.firstOrNull { it.startsWith("ANDROID_INSTALLATION=") }
            ?.substringAfter("=").orEmpty()
        val identity = when (installation) {
            "" -> "tn.biobalance.app" to "BioBalance"
            "admin" -> "tn.biobalance.app" to "BioBalance Admin"
            "responsable" -> "tn.biobalance.app.responsable" to "BioBalance Responsable"
            "vendeur" -> "tn.biobalance.app.vendeur" to "BioBalance Vendeur"
            else -> error("Unsupported Android installation")
        }
        applicationId = identity.first
        manifestPlaceholders["appLabel"] = identity.second
        val authLinkHost = defines.firstOrNull { it.startsWith("AUTH_LINK_HOST=") }?.substringAfter("=").orEmpty()
        require(authLinkHost.isEmpty() || Regex("[a-z0-9]+(?:[a-z0-9.-]*[a-z0-9])?").matches(authLinkHost)) { "AUTH_LINK_HOST must be a DNS name" }
        // Only the main installation handles verified links. Private copies use
        // manual invitation/recovery codes, without competing for the same URL.
        manifestPlaceholders["authLinkHost"] = if (installation in listOf("responsable", "vendeur"))
            "account-links.invalid" else authLinkHost.ifEmpty { "account-links.invalid" }

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

// Inspect the actual graph so aggregate tasks (assemble/bundle) cannot bypass
// the release gate by omitting "Release" from their command-line task name.
gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any {
        it.project.path == project.path && it.name.contains("release", ignoreCase = true)
    }
    if (buildsRelease) {
        require(System.getenv("BIOBALANCE_KEYSTORE") != null || System.getenv("BIOBALANCE_BUILD_MODE") == "compile-only") {
            "Release signing is required. Use scripts/build-signed-android.py or the explicit compile-only workflow."
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

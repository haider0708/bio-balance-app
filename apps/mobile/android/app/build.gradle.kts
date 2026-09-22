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
        applicationId = "tn.biobalance.app"
        val defines = (project.findProperty("dart-defines") as? String).orEmpty()
            .split(",").filter { it.isNotEmpty() }
            .map { String(Base64.getDecoder().decode(it)) }
        val authLinkHost = defines.firstOrNull { it.startsWith("AUTH_LINK_HOST=") }?.substringAfter("=").orEmpty()
        require(authLinkHost.isEmpty() || Regex("[a-z0-9]+(?:[a-z0-9.-]*[a-z0-9])?").matches(authLinkHost)) { "AUTH_LINK_HOST must be a DNS name" }
        manifestPlaceholders["authLinkHost"] = authLinkHost.ifEmpty { "account-links.invalid" }

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
            if (keystorePath != null) signingConfig = signingConfigs.getByName("production")
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

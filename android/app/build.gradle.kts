// android/app/build.gradle.kts
//
// SIGNING STRATEGY
// ----------------
// Both local release builds and GitHub Actions CI builds sign with the same
// keystore so Android accepts over-the-top APK installations without requiring
// a manual uninstall first.
//
// Local developer workflow:
//   1. Generate a keystore once:
//        keytool -genkey -v -keystore release.jks -alias pia-wireguard \
//                -keyalg RSA -keysize 2048 -validity 10000
//   2. Place release.jks somewhere OUTSIDE the repo (e.g. ~/.android/).
//   3. Create android/key.properties (already in .gitignore):
//        storeFile=/Users/andrew/.android/release.jks
//        storePassword=YOUR_STORE_PASSWORD
//        keyAlias=pia-wireguard
//        keyPassword=YOUR_KEY_PASSWORD
//
// GitHub Actions CI workflow:
//   1. Base64-encode the same JKS:  base64 -i release.jks | pbcopy
//   2. Add four repository secrets:
//        KEYSTORE_BASE64      <- the base64 blob
//        KEYSTORE_PASSWORD    <- storePassword value
//        KEY_ALIAS            <- keyAlias value
//        KEY_PASSWORD         <- keyPassword value
//   3. The release.yml workflow decodes the JKS and writes a key.properties
//      file before calling `flutter build apk --release`, so CI and local
//      builds use identical credentials.
//
// WHY THIS MATTERS
// Android enforces that every APK update must be signed by the same certificate
// as the installed version. Mixing a debug-signed local APK with a release-
// signed CI APK (or vice versa) causes a INSTALL_FAILED_UPDATE_INCOMPATIBLE
// rejection. Unifying on one release keystore eliminates this entirely.

import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Load signing credentials from android/key.properties if present.
// Falls back gracefully so the project still syncs on machines without the
// keystore file (e.g. a fresh clone before the developer sets up signing).
// ---------------------------------------------------------------------------
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.exponentiallydigital.pia_wireguard_cfga"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.exponentiallydigital.pia_wireguard_cfga"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        base.archivesName.set("pia-wireguard-cfga")
    }

    // ---------------------------------------------------------------------------
    // Signing configs
    // Release builds use the shared keystore loaded from key.properties.
    // If key.properties is absent (e.g. a cold CI clone before secrets are
    // written), the block still compiles -- the build will fail at signing time
    // with a clear error rather than silently using the debug certificate.
    // ---------------------------------------------------------------------------
    signingConfigs {
        create("release") {
            storeFile = keyProperties["storeFile"]?.let { file(it) }
            storePassword = keyProperties["storePassword"] as String?
            keyAlias = keyProperties["keyAlias"] as String?
            keyPassword = keyProperties["keyPassword"] as String?
        }
    }

    buildTypes {
        // Debug builds continue to use the default debug signing certificate.
        // They will NOT be installable over a release-signed APK -- that is
        // intentional and correct behaviour.
        getByName("debug") {
            signingConfig = signingConfigs.getByName("debug")
        }

        // Release builds use the shared keystore so local and CI APKs are
        // always signed by the same certificate.
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
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

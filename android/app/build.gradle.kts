// android/app/build.gradle.kts

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin
    id("dev.flutter.flutter-gradle-plugin")
    // The Google Services Plugin (REQUIRED for Firebase)
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.flutter_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Must match the package name in your google-services.json
        applicationId = "tripshare.group"
        
        // Firebase requires a higher Min SDK (21+). We use 23 to be safe.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Required for large apps with Firebase
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Required to prevent crash on older Android versions
    implementation("androidx.multidex:multidex:2.0.1")
    
    // Core Firebase dependencies (BoM manages versions)
    implementation(platform("com.google.firebase:firebase-bom:32.7.2"))
    implementation("com.google.code.gson:gson:2.9.1")
}
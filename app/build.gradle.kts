plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.robo.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.robo.app"
        minSdk = 23
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
    }

    // A fixed signing key lives in the repo so every new build can be installed
    // over the previous one without uninstalling. Personal use only.
    signingConfigs {
        create("robo") {
            storeFile = file("robo.keystore")
            storePassword = "robo123"
            keyAlias = "robo"
            keyPassword = "robo123"
        }
    }

    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("robo")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
}

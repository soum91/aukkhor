plugins { id("com.android.application") }
android {
    namespace = "dev.soum91.aukkhor.tv"
    compileSdk = 35
    defaultConfig {
        applicationId = "dev.soum91.aukkhor.tv"
        minSdk = 26
        targetSdk = 35
        versionCode = (project.findProperty("AUKKHOR_BUILD_NUMBER")?.toString()?.toIntOrNull() ?: 1)
        versionName = "0.3.0.$versionCode"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

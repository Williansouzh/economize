import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Chave de assinatura do release, fora do git (android/key.properties). Veja docs/DEPLOY.md.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.financas.financas_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Identidade do app na Google Play: depois de publicado, nunca pode mudar.
        applicationId = "tech.economizze.app"
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
        manifestPlaceholders["appName"] = "Economizze"
        // APK de um processador só (download da landing page): --android-project-arg=onlyAbi=arm64-v8a.
        // Sem isso, bibliotecas de plugins de outras arquiteturas entram no APK e um celular de 32 bits
        // instalaria um app que fecha ao abrir; com o filtro, ele recusa a instalação.
    }

    (project.findProperty("onlyAbi") as String?)?.let { abi ->
        packaging {
            jniLibs {
                excludes += listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
                    .filter { it != abi }
                    .map { "lib/$it/**" }
            }
        }
    }

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        // Debug instala ao lado do app da loja: outro id e outro nome no celular.
        debug {
            applicationIdSuffix = ".dev"
            manifestPlaceholders["appName"] = "Economizze Dev"
        }
        release {
            manifestPlaceholders["appName"] = "Economizze"
            // Sem key.properties, assina com a chave de debug: serve para testar, mas a Google Play recusa.
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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

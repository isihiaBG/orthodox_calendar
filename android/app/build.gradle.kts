import java.util.Properties
import java.io.FileInputStream
import java.io.InputStreamReader

// ⚠ Паролата на подписващия ключ живее в `android/key.properties`, който Е в
// .gitignore. Ако файлът липсва (пресен клон, чужда машина), билдът НЕ гърми —
// пада обратно на дебъг ключа, тъй че `flutter run --release` продължава да
// работи. Само ГОТОВИЯТ за Play релийз иска истинския ключ.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    // ⚠ ЗАДЪЛЖИТЕЛНО с изричен UTF-8. `Properties.load(InputStream)` чете
    // файла като ISO-8859-1 по подразбиране (така е от Java 1.0), тъй че
    // всяка кирилица в пътя излиза като боклук. Тук пътят до ключа минава
    // през папка „Калиник" и билдът гърмеше с подвеждащото
    // „SigningConfig "release" is missing required property storeFile" —
    // файлът си беше на място, просто името му не се разчиташе.
    keystoreProperties.load(
        InputStreamReader(FileInputStream(keystorePropertiesFile), "UTF-8"))
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "isihiabg.orthodox_calendar"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // ⚠ НЕ СЕ СМЕНЯ след първото качване в Play Store — Play го смята
        // за ДРУГО приложение и старите потребители не получават ъпдейт.
        applicationId = "isihiabg.orthodox_calendar"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storePath = keystoreProperties["storeFile"] as String?
            if (storePath != null && file(storePath).exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(storePath)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // ⚠ ПОДПИСЪТ Е НЕОБРАТИМ след първото качване в Play Store: всеки
            // следващ ъпдейт трябва да е подписан със СЪЩИЯ ключ, инак Play го
            // отказва. Затова .jks файлът и паролата се пазят и извън този
            // компютър — загубата им значи приложение, което не може да се
            // обнови никога.
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
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

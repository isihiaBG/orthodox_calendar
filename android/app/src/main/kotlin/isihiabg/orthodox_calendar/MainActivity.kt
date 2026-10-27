package isihiabg.orthodox_calendar

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// ⚠ AudioServiceActivity (audio_service): двигателят на Flutter е общ с
// услугата „медия“, тъй че четенето на глас продължава във фонов режим
// (lib/audio_background.dart).
class MainActivity : AudioServiceActivity() {
    // Актуализацията отвътре (lib/app_update.dart): отваря инсталатора на
    // Android за вече свалено и проверено APK. ⚠ Тихо инсталиране няма —
    // последната дума е на човека.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "isihiabg/update")
            .setMethodCallHandler { call, result ->
                if (call.method == "canInstall") {
                    // Даде ли човекът разрешението — Dart пуска инсталатора сам.
                    result.success(Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                        packageManager.canRequestPackageInstalls())
                    return@setMethodCallHandler
                }
                // Четенето на глас във фонов режим (lib/background_permission.dart):
                // пести ли системата батерията на приложението и как да се
                // разреши — стандартното прозорче на Android, а на
                // Honor/Huawei и техният екран „Стартиране на приложения“.
                when (call.method) {
                    "bgState" -> {
                        val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
                        result.success(mapOf(
                            "allowed" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                                pm.isIgnoringBatteryOptimizations(packageName)),
                            "vendor" to Build.MANUFACTURER.lowercase()))
                        return@setMethodCallHandler
                    }
                    "bgRequest" -> {
                        result.success(tryStart(listOf(
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName")),
                            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))))
                        return@setMethodCallHandler
                    }
                    "bgAppInfo" -> {
                        result.success(tryStart(listOf(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:$packageName")))))
                        return@setMethodCallHandler
                    }
                    "bgVendor" -> {
                        result.success(tryStart(listOf(
                            Intent("hihonor.intent.action.HSM_STARTUPAPP_MANAGER"),
                            Intent().setClassName("com.hihonor.systemmanager",
                                "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
                            Intent("huawei.intent.action.HSM_STARTUPAPP_MANAGER"),
                            Intent().setClassName("com.huawei.systemmanager",
                                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
                            Intent().setClassName("com.huawei.systemmanager",
                                "com.huawei.systemmanager.optimize.process.ProtectActivity"),
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:$packageName")))))
                        return@setMethodCallHandler
                    }
                }
                if (call.method == "audioDiag") {
                    // Дневникът на звука (lib/audio_background.dart): тече ли
                    // услугата „медия“ на преден план, пести ли системата
                    // батерията на приложението, разрешени ли са известията.
                    result.success(audioDiag())
                    return@setMethodCallHandler
                }
                if (call.method != "install") {
                    result.notImplemented(); return@setMethodCallHandler
                }
                try {
                    // Android 8+: разрешение „Инсталиране на неизвестни
                    // приложения" за НАШЕТО приложение — веднъж.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        !packageManager.canRequestPackageInstalls()) {
                        startActivity(Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName")))
                        result.success("permission"); return@setMethodCallHandler
                    }
                    val file = File(call.argument<String>("path")!!)
                    val uri = FileProvider.getUriForFile(
                        this, "$packageName.update_files", file)
                    val i = Intent(Intent.ACTION_VIEW)
                        .setDataAndType(uri, "application/vnd.android.package-archive")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                  Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(i)
                    result.success("ok")
                } catch (e: Exception) {
                    result.error("install", e.message, null)
                }
            }
    }

    // Първото намерение, което системата приема; false — нито едно.
    private fun tryStart(intents: List<Intent>): Boolean {
        for (i in intents) {
            try {
                startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (_: Exception) {}
        }
        return false
    }

    private fun audioDiag(): String = try {
        val am = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
        @Suppress("DEPRECATION")
        val svc = am.getRunningServices(50).firstOrNull {
            it.service.packageName == packageName &&
                it.service.className == "com.ryanheise.audioservice.AudioService"
        }
        val service = when {
            svc == null -> "няма"
            svc.foreground -> "на преден план"
            else -> "тече, НЕ на преден план"
        }
        val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
        val battery = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !pm.isIgnoringBatteryOptimizations(packageName)) "пести" else "свободно"
        val notif = androidx.core.app.NotificationManagerCompat.from(this)
            .areNotificationsEnabled()
        "услуга: $service; батерия: $battery; известия: ${if (notif) "да" else "НЕ"}; " +
            "${Build.MANUFACTURER} ${Build.MODEL}, Android ${Build.VERSION.RELEASE}"
    } catch (e: Exception) {
        "грешка: ${e.message}"
    }
}

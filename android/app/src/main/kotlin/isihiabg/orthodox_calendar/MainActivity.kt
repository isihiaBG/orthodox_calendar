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
}

package com.ganaderov.mobile

import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        cleanSharedPhotos()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.ganaderov.mobile/photo_share")
            .setMethodCallHandler { call, result ->
                if (call.method != "sharePhoto") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                val mime = call.argument<String>("mime")
                val extension = when (mime) {
                    "image/jpeg" -> "jpg"
                    "image/png" -> "png"
                    "image/webp" -> "webp"
                    else -> null
                }
                if (bytes == null || bytes.isEmpty() || bytes.size > 10 * 1024 * 1024 || extension == null) {
                    result.error("INVALID_PHOTO", "Fotografía inválida", null)
                    return@setMethodCallHandler
                }
                var file: File? = null
                try {
                    cleanSharedPhotos()
                    val directory = File(cacheDir, "shared_photos/${UUID.randomUUID()}")
                    check(directory.mkdirs())
                    val original = File(directory, "ganaderov-foto.$extension")
                    file = original
                    original.writeBytes(bytes)
                    val uri = FileProvider.getUriForFile(this, "$packageName.photo_share", original)
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = mime
                        putExtra(Intent.EXTRA_STREAM, uri)
                        clipData = ClipData.newRawUri("Fotografía", uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(Intent.createChooser(send, "Compartir fotografía"))
                    result.success(null)
                } catch (_: Exception) {
                    file?.parentFile?.deleteRecursively()
                    result.error("SHARE_FAILED", "No se pudo compartir la fotografía", null)
                }
            }
    }

    private fun cleanSharedPhotos() {
        val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
        File(cacheDir, "shared_photos").listFiles()?.forEach {
            if (it.lastModified() < cutoff) it.deleteRecursively()
        }
    }
}

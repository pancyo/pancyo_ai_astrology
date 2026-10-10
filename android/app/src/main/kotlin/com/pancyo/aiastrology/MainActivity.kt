package com.pancyo.aiastrology

import android.app.ActivityManager
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var manualBgmPlayer: ManualBgmPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        manualBgmPlayer?.dispose()
        val bgmPlayer = ManualBgmPlayer(this)
        manualBgmPlayer = bgmPlayer
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ManualBgmPlayer.METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    val arguments = call.arguments as? Map<*, *>
                    if (arguments?.get("loop") != true) {
                        result.success(bgmPlayer.invalidRequest("loop_required"))
                    } else {
                        result.success(bgmPlayer.play(loop = true))
                    }
                }
                "stop" -> result.success(bgmPlayer.stop())
                "setVolume" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val rawValue = arguments?.get("value") as? Number
                    val value = rawValue?.toDouble()
                    if (value == null || value.isNaN() || value.isInfinite()) {
                        result.success(bgmPlayer.invalidRequest("invalid_volume"))
                    } else if (value !in 0.0..1.0) {
                        result.success(bgmPlayer.invalidRequest("volume_out_of_range"))
                    } else {
                        result.success(bgmPlayer.setVolume(value))
                    }
                }
                "getState" -> result.success(bgmPlayer.getState())
                else -> result.notImplemented()
            }
        }
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ManualBgmPlayer.EVENT_CHANNEL,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                bgmPlayer.setEventSink(events)
            }

            override fun onCancel(arguments: Any?) {
                bgmPlayer.setEventSink(null)
            }
        })
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.pancyo.aiastrology/civil_time",
        ).setMethodCallHandler { call, result ->
            if (call.method != "resolveLocal" && call.method != "formatInstant") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                val arguments = call.arguments as? Map<*, *>
                    ?: throw IllegalArgumentException("Missing civil clock arguments")
                val zoneId = arguments["zoneId"] as? String
                    ?: throw IllegalArgumentException("Missing region ID")
                val value = if (call.method == "resolveLocal") {
                    CivilTimeResolver.resolveLocal(
                        zoneId,
                        arguments["localDate"] as? String
                            ?: throw IllegalArgumentException("Missing civil date"),
                        arguments["localTime"] as? String
                            ?: throw IllegalArgumentException("Missing civil time"),
                    )
                } else {
                    CivilTimeResolver.formatInstant(
                        zoneId,
                        arguments["instantUtc"] as? String
                            ?: throw IllegalArgumentException("Missing UTC instant"),
                    )
                }
                result.success(value)
            } catch (_: IllegalArgumentException) {
                result.error("invalid_civil_time", "Invalid region or civil clock input.", null)
            } catch (_: java.time.DateTimeException) {
                result.error("civil_time_unavailable", "Regional clock rules are unavailable.", null)
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.pancyo.aiastrology/device_memory",
        ).setMethodCallHandler { call, result ->
            if (call.method != "getMemoryInfo") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val info = ActivityManager.MemoryInfo()
            manager.getMemoryInfo(info)
            result.success(
                mapOf(
                    "memoryClassMb" to manager.memoryClass,
                    "largeMemoryClassMb" to manager.largeMemoryClass,
                    "totalMemoryMb" to (info.totalMem / (1024L * 1024L)).toInt(),
                    "availableMemoryMb" to (info.availMem / (1024L * 1024L)).toInt(),
                    "isLowRamDevice" to manager.isLowRamDevice,
                ),
            )
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.pancyo.aiastrology/share_compat",
        ).setMethodCallHandler { call, result ->
            if (call.method != "shareImage") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            try {
                val path = call.argument<String>("path")
                    ?: throw IllegalArgumentException("共有画像のパスがありません")
                val mimeType = call.argument<String>("mimeType") ?: "image/png"
                val file = File(path).canonicalFile
                val cacheRoot = cacheDir.canonicalFile
                if (!file.exists() || !file.path.startsWith("${cacheRoot.path}${File.separator}")) {
                    throw IllegalArgumentException("共有できない画像パスです")
                }
                // share_plusが登録するFileProviderはcache/share_plusだけを公開するため、
                // 生成直後の一時PNGを共有用キャッシュへ複製してからURI化する。
                val shareDirectory = File(cacheRoot, "share_plus")
                if (!shareDirectory.exists() && !shareDirectory.mkdirs()) {
                    throw IllegalStateException("共有用フォルダを作成できませんでした")
                }
                val sharedFile = File(shareDirectory, file.name)
                file.copyTo(sharedFile, overwrite = true)

                val uri = FileProvider.getUriForFile(
                    this,
                    "$packageName.flutter.share_provider",
                    sharedFile,
                )
                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                    type = mimeType
                    putExtra(Intent.EXTRA_STREAM, uri)
                    clipData = ClipData.newRawUri("pancyo_share", uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                packageManager.queryIntentActivities(shareIntent, PackageManager.MATCH_DEFAULT_ONLY)
                    .forEach { resolveInfo ->
                        grantUriPermission(
                            resolveInfo.activityInfo.packageName,
                            uri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION,
                        )
                    }
                startActivity(Intent.createChooser(shareIntent, null))
                result.success(true)
            } catch (error: Throwable) {
                result.error("share_compat_failed", error.message, null)
            }
        }
    }

    override fun onPause() {
        manualBgmPlayer?.stop()
        super.onPause()
    }

    override fun onDestroy() {
        manualBgmPlayer?.dispose()
        manualBgmPlayer = null
        super.onDestroy()
    }
}

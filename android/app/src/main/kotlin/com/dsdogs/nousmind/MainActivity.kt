package com.dsdogs.nousmind

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Bridges Quick Settings Tile clicks to the Dart side.
 *
 * Cold-start path: QuickAddTileService.onClick() launches this Activity
 * with the OPEN_QUICK_ADD intent extra. onCreate() / onNewIntent() sets
 * [pendingQuickAdd] = true. Once the Flutter engine is up, Dart calls
 * `consumePendingQuickAdd`; we hand back the flag and clear it.
 *
 * Hot-start path: the same launch lands via onNewIntent() on an
 * already-running Activity; we then actively invoke
 * `openCreateReminder` on the channel so Dart navigates immediately
 * without waiting for the post-frame callback to drain the pending
 * flag.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "quick_settings_tile"
        private const val APP_SETTINGS_CHANNEL = "app_settings"
        const val EXTRA_OPEN_QUICK_ADD = "OPEN_QUICK_ADD"
        const val EXTRA_SCREENSHOT_PATH = "SCREENSHOT_PATH"
    }

    private var tileChannel: MethodChannel? = null
    private var ocrChannel: MethodChannel? = null
    private var appSettingsChannel: MethodChannel? = null

    /**
     * Set when a tile click arrived while Dart was not yet listening.
     */
    private val pendingQuickAdd: AtomicBoolean = AtomicBoolean(false)
    private var pendingScreenshotPath: String? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliverIfQuickAdd(intent)
        deliverIfScreenshot(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        )
        tileChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumePendingQuickAdd" -> {
                    val pending = pendingQuickAdd.getAndSet(false)
                    result.success(pending)
                }
                "consumePendingScreenshot" -> {
                    val path = pendingScreenshotPath
                    pendingScreenshotPath = null
                    result.success(path)
                }
                "isAccessibilityServiceEnabled" -> {
                    result.success(ScreenshotAccessibilityService.instance != null)
                }
                "openAccessibilitySettings" -> {
                    try {
                        val settingsIntent = Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(settingsIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        registerChineseOcrChannels(flutterEngine)
        registerAppSettingsChannel(flutterEngine)

        intent?.let {
            deliverIfQuickAdd(it)
            deliverIfScreenshot(it)
        }
    }

    private fun registerChineseOcrChannels(flutterEngine: FlutterEngine) {
        val method = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "chinese_ocr_module",
        )
        ocrChannel = method
        method.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkModule" -> result.success("installed")
                "requestDownload" -> result.success("installed")
                else -> result.notImplemented()
            }
        }
    }

    private fun registerAppSettingsChannel(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_SETTINGS_CHANNEL,
        )
        appSettingsChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "openAppSettings" -> {
                    val launched = try {
                        val settingsIntent = Intent(
                            android.provider.Settings
                                .ACTION_APPLICATION_DETAILS_SETTINGS,
                        ).apply {
                            data = android.net.Uri.fromParts(
                                "package",
                                packageName,
                                null,
                            )
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(settingsIntent)
                        true
                    } catch (error: Exception) {
                        false
                    }
                    result.success(launched)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        ocrChannel?.setMethodCallHandler(null)
        ocrChannel = null
        tileChannel?.setMethodCallHandler(null)
        tileChannel = null
        appSettingsChannel?.setMethodCallHandler(null)
        appSettingsChannel = null
        super.onDestroy()
    }

    private fun deliverIfQuickAdd(intent: Intent) {
        if (!intent.getBooleanExtra(EXTRA_OPEN_QUICK_ADD, false)) return
        intent.removeExtra(EXTRA_OPEN_QUICK_ADD)
        pendingQuickAdd.set(true)
        tileChannel?.invokeMethod("openCreateReminder", null)
    }

    private fun deliverIfScreenshot(intent: Intent) {
        val path = intent.getStringExtra(EXTRA_SCREENSHOT_PATH) ?: return
        intent.removeExtra(EXTRA_SCREENSHOT_PATH)
        pendingScreenshotPath = path
        tileChannel?.invokeMethod("openScreenshotAnalysis", path)
    }
}

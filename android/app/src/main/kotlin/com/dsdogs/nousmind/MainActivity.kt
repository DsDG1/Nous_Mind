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
    }

    private var tileChannel: MethodChannel? = null
    private var ocrChannel: MethodChannel? = null
    private var appSettingsChannel: MethodChannel? = null

    /**
     * Set when a tile click arrived while Dart was not yet listening.
     * Consumed atomically by the first Dart `consumePendingQuickAdd`
     * call after engine boot. An instance field is sufficient because
     * the field is only read by the same [MainActivity] instance that
     * wrote it; the bridge forwards the click into Dart before the
     * process can be torn down.
     */
    private val pendingQuickAdd: AtomicBoolean = AtomicBoolean(false)

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliverIfQuickAdd(intent)
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
                else -> result.notImplemented()
            }
        }

        registerChineseOcrChannels(flutterEngine)
        registerAppSettingsChannel(flutterEngine)

        // The current intent (set in onCreate or by onNewIntent) may
        // already be carrying a quick-add request. Drain it now so a
        // single-tap, single-handler delivery works in every order.
        intent?.let { deliverIfQuickAdd(it) }
    }

    /**
     * Wires the `chinese_ocr_module` MethodChannel used by
     * `lib/services/chinese_ocr_installer.dart`.
     *
     * The Chinese model is statically linked into the APK via the
     * `com.google.mlkit:text-recognition-chinese` dependency in
     * `app/build.gradle.kts`, so the runtime answer to "is the model
     * available?" is unconditionally "installed" on Android. We keep
     * the channel anyway so the Dart side can probe the state through
     * a single, future-proof entry point — if a future release moves
     * to an unbundled Play Services module, only this handler needs
     * to change.
     */
    private fun registerChineseOcrChannels(flutterEngine: FlutterEngine) {
        val method = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "chinese_ocr_module",
        )
        ocrChannel = method
        method.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkModule" -> result.success("installed")
                // Kept for API symmetry with the Dart installer. With
                // the bundled model there is nothing to download —
                // we just report the current (always installed)
                // state.
                "requestDownload" -> result.success("installed")
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Wires the `app_settings` MethodChannel used by
     * `lib/services/app_settings_bridge.dart`.
     *
     * Lets Dart jump straight to the OS app-details screen so users who
     * previously denied the calendar permission can re-enable it
     * without hunting through system Settings. Mirrors the existing
     * `chinese_ocr_module` and `quick_settings_tile` channels.
     */
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
                        val intent = Intent(
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
                        startActivity(intent)
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

    /**
     * If the intent carries a quick-add request, mark the pending flag
     * (so a future Dart consumePending call also handles it, in case the
     * channel handler is not yet installed) and proactively invoke the
     * openCreateReminder method to trigger the Dart hot-path handler.
     */
    private fun deliverIfQuickAdd(intent: Intent) {
        if (!intent.getBooleanExtra(EXTRA_OPEN_QUICK_ADD, false)) return
        // Clear the extra so a config-change re-delivery doesn't fire twice.
        intent.removeExtra(EXTRA_OPEN_QUICK_ADD)
        pendingQuickAdd.set(true)
        tileChannel?.invokeMethod("openCreateReminder", null)
    }
}

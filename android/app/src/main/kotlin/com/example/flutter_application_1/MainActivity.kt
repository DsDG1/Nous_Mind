package com.example.flutter_application_1

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
        const val EXTRA_OPEN_QUICK_ADD = "OPEN_QUICK_ADD"

        /**
         * Set when a tile click arrived while Dart was not yet listening.
         * Consumed atomically by the first Dart `consumePendingQuickAdd`
         * call after engine boot. Static so it survives Activity
         * recreation within the same process.
         */
        @JvmStatic
        val pendingQuickAdd: AtomicBoolean = AtomicBoolean(false)
    }

    private var tileChannel: MethodChannel? = null

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

        // The current intent (set in onCreate or by onNewIntent) may
        // already be carrying a quick-add request. Drain it now so a
        // single-tap, single-handler delivery works in every order.
        intent?.let { deliverIfQuickAdd(it) }
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

package com.example.flutter_application_1

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "screenshot_service"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPendingScreenshot" -> {
                    val path = checkPendingScreenshotPath()
                    if (path != null) {
                        result.success(path)
                    } else {
                        result.success(null)
                    }
                }
                "clearPendingScreenshot" -> {
                    clearPendingScreenshotPath()
                    result.success(null)
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(null)
                }
                "hasOverlayPermission" -> {
                    result.success(hasOverlayPermission())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun checkPendingScreenshotPath(): String? {
        val prefs = getSharedPreferences(
            ScreenshotCaptureActivity.PREFS_NAME,
            Context.MODE_PRIVATE,
        )
        return prefs.getString(ScreenshotCaptureActivity.KEY_PENDING_PATH, null)
    }

    private fun clearPendingScreenshotPath() {
        getSharedPreferences(
            ScreenshotCaptureActivity.PREFS_NAME,
            Context.MODE_PRIVATE,
        ).edit()
            .remove(ScreenshotCaptureActivity.KEY_PENDING_PATH)
            .apply()
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName"),
            )
            startActivity(intent)
        }
    }

    private fun hasOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }
}

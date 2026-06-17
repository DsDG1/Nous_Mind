package com.dsdogs.nousmind

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.view.Display
import java.io.File
import java.io.FileOutputStream

class ScreenshotAccessibilityService : AccessibilityService() {

    companion object {
        var instance: ScreenshotAccessibilityService? = null
            private set
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: android.view.accessibility.AccessibilityEvent?) {
        // No-op: we only need the screenshot privilege, we don't inspect events
    }

    override fun onInterrupt() {
        // No-op
    }

    private fun cleanOldScreenshots(cacheDir: File) {
        try {
            val files = cacheDir.listFiles()
            if (files != null) {
                for (file in files) {
                    if (file.name.startsWith("screenshot_analysis_") && file.name.endsWith(".jpg")) {
                        file.delete()
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun captureSilently(onComplete: (Boolean, String?) -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            takeScreenshot(Display.DEFAULT_DISPLAY, mainExecutor, object : TakeScreenshotCallback {
                override fun onSuccess(screenshotResult: ScreenshotResult) {
                    try {
                        val hardwareBitmap = Bitmap.wrapHardwareBuffer(
                            screenshotResult.hardwareBuffer,
                            screenshotResult.colorSpace
                        )
                        if (hardwareBitmap != null) {
                            val softwareBitmap = hardwareBitmap.copy(Bitmap.Config.ARGB_8888, false)
                            val cacheDir = cacheDir
                            cleanOldScreenshots(cacheDir)
                            val screenshotFile = File(cacheDir, "screenshot_analysis_${System.currentTimeMillis()}.jpg")
                            FileOutputStream(screenshotFile).use { out ->
                                softwareBitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
                            }
                            onComplete(true, screenshotFile.absolutePath)
                            return
                        }
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                    onComplete(false, null)
                }

                override fun onFailure(errorCode: Int) {
                    onComplete(false, null)
                }
            })
        } else {
            onComplete(false, null)
        }
    }
}

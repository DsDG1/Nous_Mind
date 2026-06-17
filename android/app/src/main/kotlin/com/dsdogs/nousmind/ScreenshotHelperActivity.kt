package com.dsdogs.nousmind

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast
import android.os.Handler
import android.os.Looper
import java.io.File

class ScreenshotHelperActivity : Activity() {

    companion object {
        private const val REQUEST_MEDIA_PROJECTION = 1001
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Delay execution by 1 second (1000ms) to allow notification shade collapse to finish,
        // returning the user visually to the original app screen before taking screenshot or showing prompt.
        Handler(Looper.getMainLooper()).postDelayed({
            if (!isFinishing && !isDestroyed) {
                proceedFlow()
            }
        }, 1000)
    }

    private fun proceedFlow() {
        val accessibilityService = ScreenshotAccessibilityService.instance
        if (accessibilityService != null) {
            // Service is active: take a silent screenshot, then confirm on top of original app
            accessibilityService.captureSilently { success, path ->
                if (success && path != null) {
                    showAnalysisConfirmDialog(path)
                } else {
                    Toast.makeText(this, "截图失败，请重试", Toast.LENGTH_SHORT).show()
                    finish()
                }
            }
        } else {
            // Not active: show the choice dialog
            showChoiceDialog()
        }
    }

    private fun getDialogTheme(): Int {
        val isDarkMode = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) == android.content.res.Configuration.UI_MODE_NIGHT_YES
        return if (isDarkMode) {
            android.R.style.Theme_DeviceDefault_Dialog_Alert
        } else {
            android.R.style.Theme_DeviceDefault_Light_Dialog_Alert
        }
    }

    private fun showAnalysisConfirmDialog(imagePath: String) {
        val builder = AlertDialog.Builder(this, getDialogTheme())
        builder.setTitle("屏幕分析助手")
        builder.setMessage("屏幕截图已捕获。是否开启 AI 智能分析并生成提醒事项？")
        
        builder.setPositiveButton("开始分析") { _, _ ->
            val launchIntent = Intent(this, MainActivity::class.java).apply {
                putExtra(MainActivity.EXTRA_SCREENSHOT_PATH, imagePath)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            startActivity(launchIntent)
            finish()
        }

        builder.setNegativeButton("取消") { _, _ ->
            deleteTempFile(imagePath)
            finish()
        }

        builder.setOnCancelListener {
            deleteTempFile(imagePath)
            finish()
        }

        builder.show()
    }

    private fun deleteTempFile(path: String) {
        try {
            val file = File(path)
            if (file.exists()) {
                file.delete()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun showChoiceDialog() {
        val builder = AlertDialog.Builder(this, getDialogTheme())
        builder.setTitle("屏幕分析助手")
        builder.setMessage("启用「无感截图」后，点击磁贴可免弹窗静默截图；否则每次截图都需要手动点击投屏授权。")
        
        builder.setPositiveButton("开启无感截图") { _, _ ->
            try {
                val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                Toast.makeText(this, "请在列表中找到并启用「NousMind 屏幕分析助手」", Toast.LENGTH_LONG).show()
            } catch (e: Exception) {
                e.printStackTrace()
            }
            finish()
        }

        builder.setNeutralButton("单次弹窗截图") { _, _ ->
            startMediaProjectionRequest()
        }

        builder.setNegativeButton("取消") { _, _ ->
            finish()
        }

        builder.setOnCancelListener {
            finish()
        }

        builder.show()
    }

    private fun startMediaProjectionRequest() {
        val projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(projectionManager.createScreenCaptureIntent(), REQUEST_MEDIA_PROJECTION)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_MEDIA_PROJECTION) {
            if (resultCode == RESULT_OK && data != null) {
                // Start ScreenshotService
                val serviceIntent = Intent(this, ScreenshotService::class.java).apply {
                    putExtra(ScreenshotService.EXTRA_RESULT_CODE, resultCode)
                    putExtra(ScreenshotService.EXTRA_RESULT_DATA, data)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }
            }
        }
        finish()
    }
}

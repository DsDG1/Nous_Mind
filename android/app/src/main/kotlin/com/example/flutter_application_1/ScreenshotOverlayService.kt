package com.example.flutter_application_1

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.BitmapFactory
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import java.io.File

/**
 * Foreground service that shows a floating overlay window with the captured
 * screenshot. The overlay has two buttons:
 *
 * - **[保存到提醒]** – stores the screenshot and launches the Flutter app.
 * - **[关闭]** – dismisses the overlay and deletes the temporary image.
 */
class ScreenshotOverlayService : Service() {

    companion object {
        private const val TAG = "ScreenshotOverlay"
        private const val CHANNEL_ID = "screenshot_overlay_channel"
        private const val NOTIFICATION_ID = 2001
    }

    private lateinit var windowManager: WindowManager
    private var overlayView: View? = null
    private var screenshotPath: String? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        screenshotPath = intent?.getStringExtra("screenshot_path")
        if (screenshotPath == null) {
            Log.w(TAG, "No screenshot path provided")
            stopSelf()
            return START_NOT_STICKY
        }
        startForeground(NOTIFICATION_ID, buildNotification())
        showOverlay()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "截图悬浮窗",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "显示截图悬浮窗时所需的通知"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("截图已捕获")
                .setContentText("点击返回应用")
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("截图已捕获")
                .setContentText("点击返回应用")
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        }
    }

    @Suppress("DEPRECATION")
    private fun showOverlay() {
        val path = screenshotPath ?: return
        val file = File(path)
        if (!file.exists()) {
            Log.w(TAG, "Screenshot file not found: $path")
            stopSelf()
            return
        }

        val inflater = getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(8, 8, 8, 8)
            setBackgroundColor(0xFF222222.toInt())
            gravity = Gravity.CENTER
        }

        val imageView = ImageView(this).apply {
            val bitmap = BitmapFactory.decodeFile(path)
            setImageBitmap(bitmap)
            adjustViewBounds = true
            scaleType = ImageView.ScaleType.FIT_CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                800,
            )
        }

        val buttonLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, 8, 0, 0)
        }

        val saveButton = Button(this).apply {
            text = "保存到提醒"
            setOnClickListener {
                // Store path so Flutter reads it on resume.
                getSharedPreferences(
                    ScreenshotCaptureActivity.PREFS_NAME,
                    Context.MODE_PRIVATE,
                ).edit()
                    .putString(ScreenshotCaptureActivity.KEY_PENDING_PATH, path)
                    .apply()

                // Launch the app.
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                if (launchIntent != null) {
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    startActivity(launchIntent)
                }
                dismissOverlayAndStop()
            }
        }

        val closeButton = Button(this).apply {
            text = "关闭"
            setOnClickListener {
                // Delete the temporary screenshot.
                file.delete()
                getSharedPreferences(
                    ScreenshotCaptureActivity.PREFS_NAME,
                    Context.MODE_PRIVATE,
                ).edit()
                    .remove(ScreenshotCaptureActivity.KEY_PENDING_PATH)
                    .apply()
                dismissOverlayAndStop()
            }
        }

        buttonLayout.addView(saveButton)
        buttonLayout.addView(closeButton)
        layout.addView(imageView)
        layout.addView(buttonLayout)

        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.CENTER
        }

        overlayView = layout
        windowManager.addView(layout, params)
    }

    private fun dismissOverlayAndStop() {
        try {
            overlayView?.let { windowManager.removeView(it) }
        } catch (_: Exception) {
        }
        overlayView = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        dismissOverlayAndStop()
        super.onDestroy()
    }
}

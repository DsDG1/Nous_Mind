package com.example.flutter_application_1

import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log

/**
 * Quick Settings tile that initiates a screenshot capture.
 *
 * When the user taps the tile the notification shade is collapsed and a
 * transparent [ScreenshotCaptureActivity] is launched to request the
 * MediaProjection permission and perform the actual capture.
 */
class ScreenshotTileService : TileService() {

    companion object {
        private const val TAG = "ScreenshotTile"
    }

    override fun onClick() {
        super.onClick()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            startActivityAndCollapse(
                Intent(this, ScreenshotCaptureActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(
                Intent(this, ScreenshotCaptureActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    override fun onTileAdded() {
        super.onTileAdded()
        Log.d(TAG, "Tile added – user can now capture screenshots from Quick Settings")
    }

    override fun onTileRemoved() {
        super.onTileRemoved()
        Log.d(TAG, "Tile removed")
    }

    override fun onStartListening() {
        super.onStartListening()
        qsTile?.state = Tile.STATE_ACTIVE
        qsTile?.updateTile()
    }

    override fun onStopListening() {
        super.onStopListening()
    }
}

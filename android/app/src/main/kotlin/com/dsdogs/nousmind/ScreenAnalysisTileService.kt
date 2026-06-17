package com.dsdogs.nousmind

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class ScreenAnalysisTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        qsTile.state = Tile.STATE_INACTIVE
        qsTile.updateTile()
    }

    override fun onClick() {
        super.onClick()

        qsTile.state = Tile.STATE_ACTIVE
        qsTile.updateTile()

        // Always collapse notification shade and open the helper activity
        val launchIntent = Intent().apply {
            component = ComponentName(
                this@ScreenAnalysisTileService,
                ScreenshotHelperActivity::class.java,
            )
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                1,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            startActivityAndCollapse(pendingIntent)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            startActivityAndCollapse(launchIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivity(launchIntent)
        }

        // Reset tile state back to inactive for the next click
        qsTile.state = Tile.STATE_INACTIVE
        qsTile.updateTile()
    }

    override fun onStopListening() {
        super.onStopListening()
        qsTile.state = Tile.STATE_INACTIVE
        qsTile.updateTile()
    }
}

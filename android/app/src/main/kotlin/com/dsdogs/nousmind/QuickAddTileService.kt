package com.dsdogs.nousmind

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Quick Settings tile that opens the in-app reminder editor.
 *
 * Non-toggleable (ACTIVE_TILE meta-data = false in the manifest). The
 * tile is purely an action button — tapping it always launches
 * MainActivity with the OPEN_QUICK_ADD extra and brings the app to
 * the foreground. MainActivity.onNewIntent then forwards the request
 * to the Dart side via MethodChannel("quick_settings_tile"), so the
 * editor opens whether the app was already alive or just cold-started.
 */
class QuickAddTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        // Reset to a neutral visual whenever the QS panel is opened.
        qsTile.state = Tile.STATE_INACTIVE
        qsTile.updateTile()
    }

    override fun onClick() {
        super.onClick()

        // Briefly show the active state for tap acknowledgement.
        qsTile.state = Tile.STATE_ACTIVE
        qsTile.updateTile()

        // Bring MainActivity forward with the OPEN_QUICK_ADD extra.
        // MainActivity.onNewIntent forwards the extra to Dart through
        // the MethodChannel.
        //
        // The flag combination matters: TileService runs in a non-Activity
        // context, so FLAG_ACTIVITY_NEW_TASK is required. SINGLE_TOP +
        // REORDER_TO_FRONT ensure the existing app task is brought to the
        // foreground and the existing MainActivity instance is reused
        // (manifest declares launchMode="singleTop", so onNewIntent fires
        // instead of a fresh onCreate). CLEAR_TOP was removed because,
        // combined with the empty taskAffinity on MainActivity and
        // NEW_TASK from a non-Activity context, it could strand the
        // activity in an isolated task — the user sees the QS panel
        // collapse and the launcher behind it. REORDER_TO_FRONT avoids
        // that by explicitly promoting the existing task.
        //
        // startActivityAndCollapse is REQUIRED on Android 12+ for QS
        // tiles; calling startActivity directly throws RuntimeException
        // there. On Android 14+ (API 34), the Intent overload is
        // deprecated and the PendingIntent variant must be used instead.
        val launchIntent = Intent().apply {
            component = ComponentName(
                this@QuickAddTileService,
                MainActivity::class.java,
            )
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
            )
            putExtra(MainActivity.EXTRA_OPEN_QUICK_ADD, true)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
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
    }

    override fun onStopListening() {
        super.onStopListening()
        qsTile.state = Tile.STATE_INACTIVE
        qsTile.updateTile()
    }
}

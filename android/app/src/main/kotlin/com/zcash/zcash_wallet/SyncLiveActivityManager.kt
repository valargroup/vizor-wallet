package com.zcash.zcash_wallet

import android.app.Notification
import android.content.Context
import android.widget.RemoteViews
import com.istornz.live_activities.LiveActivityManager

class SyncLiveActivityManager(private val context: Context) : LiveActivityManager() {

    override suspend fun buildNotification(
        notification: Notification.Builder,
        event: String,
        data: Map<String, Any>
    ): Notification {
        val remoteView = RemoteViews(context.packageName, R.layout.live_activity)
        val bigRemoteView = RemoteViews(context.packageName, R.layout.live_activity_expanded)

        val status = data["status"] as? String ?: "Syncing..."
        val percentage = data["percentage"] as? Double ?: 0.0
        val scannedHeight = (data["scannedHeight"] as? Number)?.toLong() ?: 0
        val chainTipHeight = (data["chainTipHeight"] as? Number)?.toLong() ?: 0
        val progress = (percentage * 100).toInt()

        // Compact view
        remoteView.setTextViewText(R.id.tv_status, status)
        remoteView.setProgressBar(R.id.pb_sync, 100, progress, false)

        // Expanded view
        bigRemoteView.setTextViewText(R.id.tv_status_expanded, status)
        bigRemoteView.setTextViewText(
            R.id.tv_block_info,
            "Block $scannedHeight / $chainTipHeight"
        )
        bigRemoteView.setProgressBar(R.id.pb_sync_expanded, 100, progress, false)

        notification
            .setSmallIcon(android.R.drawable.ic_popup_sync)
            .setCustomContentView(remoteView)
            .setCustomBigContentView(bigRemoteView)
            .setOngoing(true)
            .setSilent(true)

        return notification.build()
    }
}

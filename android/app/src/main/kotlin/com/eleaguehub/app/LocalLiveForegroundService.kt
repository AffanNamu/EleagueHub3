package com.eleaguehub.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.PendingIntentCompat

class LocalLiveForegroundService : Service() {

    companion object {
        const val ACTION_START = "com.eleaguehub.app.LOCAL_LIVE_START"
        const val ACTION_STOP  = "com.eleaguehub.app.LOCAL_LIVE_STOP"

        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT  = "text"

        private const val CHANNEL_ID = "local_live_stream"
        private const val CHANNEL_NAME = "Live Streaming"
        private const val NOTIF_ID = 4242
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "Live streaming"
                val text = intent.getStringExtra(EXTRA_TEXT) ?: "Broadcasting is running"
                startAsForeground(title, text)
            }
            ACTION_STOP -> {
                try {
                    stopForeground(true)
                } catch (_: Throwable) {
                }
                releaseWakeLock()
                stopSelf()
            }
        }
        return START_STICKY
    }

    private fun startAsForeground(title: String, text: String) {
        createChannelIfNeeded()
        val notification = buildNotification(title, text)
        startForeground(NOTIF_ID, notification)
        acquireWakeLock()
    }

    private fun buildNotification(title: String, text: String) = run {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = if (launchIntent != null) {
            PendingIntentCompat.getActivity(
                this,
                0,
                launchIntent,
                PendingIntentCompat.FLAG_IMMUTABLE or PendingIntentCompat.FLAG_UPDATE_CURRENT,
                false
            )
        } else {
            null
        }

        val b = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)

        if (contentIntent != null) {
            b.setContentIntent(contentIntent)
        }

        b.build()
    }

    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = nm.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return

        val ch = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW
        )
        ch.description = "Keeps the app alive while streaming"
        nm.createNotificationChannel(ch)
    }

    private fun acquireWakeLock() {
        try {
            if (wakeLock != null && wakeLock!!.isHeld) return
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "eleaguehub:local_live")
            wakeLock?.setReferenceCounted(false)
            wakeLock?.acquire()
        } catch (_: Throwable) {
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock != null && wakeLock!!.isHeld) {
                wakeLock?.release()
            }
        } catch (_: Throwable) {
        } finally {
            wakeLock = null
        }
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }
}

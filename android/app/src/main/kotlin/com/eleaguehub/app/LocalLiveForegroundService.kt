package com.eleaguehub.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

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
                stopForeground(true)
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

    private fun buildNotification(title: String, text: String): Notification {
        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                Notification.Builder(this)
            }

        builder
            .setContentTitle(title)
            .setContentText(text)
            // Smaller mic-style icon instead of large video presence icon
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setOnlyAlertOnce(true)

        return builder.build()
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
        ch.description = "Keeps the app alive while streaming your screen/camera"
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
            // Some OEMs may restrict; ignore
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

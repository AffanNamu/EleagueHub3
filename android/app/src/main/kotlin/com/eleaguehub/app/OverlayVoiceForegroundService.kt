package com.eleaguehub.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel

/**
 * Summary:
 * - Foreground service used while voice is active (keeps process alive + provides controls).
 * - Notification actions: Mute/Unmute, End, Expand.
 * - Sends actions to Flutter via MethodChannel when engine is alive.
 * - Safe on Android 14+: if starting microphone-type FGS fails (missing mic permission),
 *   fallback to "no-type" foreground.
 */
class OverlayVoiceForegroundService : Service() {

    companion object {
        const val ACTION_START = "com.eleaguehub.app.OVERLAY_VOICE_FGS_START"
        const val ACTION_STOP = "com.eleaguehub.app.OVERLAY_VOICE_FGS_STOP"

        private const val ACTION_TOGGLE_MUTE = "com.eleaguehub.app.OVERLAY_VOICE_TOGGLE_MUTE"
        private const val ACTION_END = "com.eleaguehub.app.OVERLAY_VOICE_END"
        private const val ACTION_EXPAND = "com.eleaguehub.app.OVERLAY_VOICE_EXPAND"

        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"

        private const val CHANNEL_ID = "overlay_voice"
        private const val CHANNEL_NAME = "Voice Chat"
        private const val NOTIF_ID = 7331

        private const val DART_CHANNEL = "local_live"
        private const val DART_METHOD_OVERLAY_ACTION = "overlayAction"
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    private var isMuted: Boolean = false
    private var currentTitle: String = "Voice chat"
    private var currentText: String = "Voice chat is running"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                currentTitle = intent.getStringExtra(EXTRA_TITLE) ?: currentTitle
                currentText = intent.getStringExtra(EXTRA_TEXT) ?: currentText
                startAsForeground()
            }

            ACTION_STOP -> {
                stopForegroundCompat()
                stopSelf()
            }

            ACTION_TOGGLE_MUTE -> {
                isMuted = !isMuted
                sendToDart(if (isMuted) "mute" else "unmute")
                updateNotification()
            }

            ACTION_END -> {
                sendToDart("end")
                stopForegroundCompat()
                stopSelf()
            }

            ACTION_EXPAND -> {
                // Always works even if Dart engine is gone: brings app to foreground.
                try {
                    val launch = packageManager.getLaunchIntentForPackage(packageName)
                    if (launch != null) {
                        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        startActivity(launch)
                    }
                } catch (_: Throwable) { }
                // Also notify Dart if possible (optional).
                sendToDart("expand")
            }
        }

        return START_STICKY
    }

    private fun startAsForeground() {
        createChannelIfNeeded()

        val notification = buildNotification()

        // Try correct microphone-type FGS first; fallback to non-typed FGS if restricted.
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIF_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                )
            } else {
                startForeground(NOTIF_ID, notification)
            }
        } catch (_: SecurityException) {
            // Missing mic permission or OEM restriction: keep service alive without type.
            try {
                startForeground(NOTIF_ID, notification)
            } catch (_: Throwable) {
                // If even this fails, stop service.
                stopSelf()
            }
        } catch (_: Throwable) {
            try {
                startForeground(NOTIF_ID, notification)
            } catch (_: Throwable) {
                stopSelf()
            }
        }
    }

    private fun stopForegroundCompat() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Throwable) {
        }
    }

    private fun updateNotification() {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIF_ID, buildNotification())
        } catch (_: Throwable) {
        }
    }

    private fun buildNotification(): Notification {
        val expandIntent = PendingIntent.getService(
            this,
            200,
            Intent(this, OverlayVoiceForegroundService::class.java).apply { action = ACTION_EXPAND },
            pendingFlags()
        )

        val muteIntent = PendingIntent.getService(
            this,
            201,
            Intent(this, OverlayVoiceForegroundService::class.java).apply { action = ACTION_TOGGLE_MUTE },
            pendingFlags()
        )

        val endIntent = PendingIntent.getService(
            this,
            202,
            Intent(this, OverlayVoiceForegroundService::class.java).apply { action = ACTION_END },
            pendingFlags()
        )

        val muteLabel = if (isMuted) "Unmute" else "Mute"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle(currentTitle)
            .setContentText(currentText)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(NotificationCompat.Action(0, muteLabel, muteIntent))
            .addAction(NotificationCompat.Action(0, "End", endIntent))
            .addAction(NotificationCompat.Action(0, "Expand", expandIntent))
            .build()
    }

    private fun pendingFlags(): Int {
        val base = PendingIntent.FLAG_UPDATE_CURRENT
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) base or PendingIntent.FLAG_IMMUTABLE else base
    }

    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return

        val ch = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW)
        ch.description = "Keeps voice chat running with overlay controls"
        nm.createNotificationChannel(ch)
    }

    private fun sendToDart(action: String) {
        val messenger = FlutterEngineHolder.messengerOrNull() ?: return

        mainHandler.post {
            try {
                val ch = MethodChannel(messenger, DART_CHANNEL)
                ch.invokeMethod(
                    DART_METHOD_OVERLAY_ACTION,
                    mapOf("action" to action)
                )
            } catch (_: Throwable) {
            }
        }
    }
}

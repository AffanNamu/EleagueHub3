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
 * - Notification actions: Toggle Mute, End, Expand.
 * - Mute label is derived from last known mic state persisted by Flutter (overlay_prefs mic_muted).
 * - Toggle action sends "toggle_mic" to Flutter; Flutter updates mic state and then pushes
 *   setOverlayMicMutedState() which updates prefs and overlay icon.
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

        private const val OVERLAY_PREFS = "overlay_prefs"
        private const val KEY_MIC_MUTED = "mic_muted"
    }

    private val mainHandler = Handler(Looper.getMainLooper())

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
                // Do not guess state here; ask Flutter to toggle.
                sendToDart("toggle_mic")

                // Update notification after a short delay to pick up prefs updated by Flutter.
                mainHandler.postDelayed({ updateNotification() }, 350)
            }

            ACTION_END -> {
                sendToDart("end")
                stopForegroundCompat()
                stopSelf()
            }

            ACTION_EXPAND -> {
                try {
                    val launch = packageManager.getLaunchIntentForPackage(packageName)
                    if (launch != null) {
                        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        startActivity(launch)
                    }
                } catch (_: Throwable) { }
                sendToDart("expand")
            }
        }

        return START_STICKY
    }

    private fun startAsForeground() {
        createChannelIfNeeded()

        val notification = buildNotification()

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
            try {
                startForeground(NOTIF_ID, notification)
            } catch (_: Throwable) {
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

    private fun isMutedFromPrefs(): Boolean {
        return try {
            val sp = applicationContext.getSharedPreferences(OVERLAY_PREFS, Context.MODE_PRIVATE)
            sp.getBoolean(KEY_MIC_MUTED, true)
        } catch (_: Throwable) {
            true
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

        val muted = isMutedFromPrefs()
        val muteLabel = if (muted) "Unmute" else "Mute"

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

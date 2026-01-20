package com.eleaguehub.app

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.*
import android.widget.ImageView
import androidx.core.content.ContextCompat

class LiveOverlayBubbleService : Service() {

    companion object {
        const val ACTION_SHOW = "com.eleaguehub.app.LIVE_OVERLAY_SHOW"
        const val ACTION_HIDE = "com.eleaguehub.app.LIVE_OVERLAY_HIDE"
    }

    private var windowManager: WindowManager? = null
    private var bubbleView: View? = null
    private var audioManager: AudioManager? = null

    // For drag
    private var initialX: Int = 0
    private var initialY: Int = 0
    private var initialTouchX: Float = 0f
    private var initialTouchY: Float = 0f

    // Audio mute state
    private var isMuted: Boolean = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> showBubble()
            ACTION_HIDE -> {
                hideBubble()
                stopSelf()
            }
        }
        return START_STICKY
    }

    private fun showBubble() {
        if (bubbleView != null) return

        // Check overlay permission
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !Settings.canDrawOverlays(this)
        ) {
            return
        }

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        val size = (48 * resources.displayMetrics.density).toInt()

        val imageView = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_btn_speak_now)
            // Very transparent
            alpha = 0.5f
            setColorFilter(
                ContextCompat.getColor(
                    this@LiveOverlayBubbleService,
                    android.R.color.white
                ),
                android.graphics.PorterDuff.Mode.SRC_ATOP
            )
        }

        val layoutType =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

        val params = WindowManager.LayoutParams(
            size,
            size,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )

        // Start top-right
        params.gravity = Gravity.TOP or Gravity.END
        params.x = 20
        params.y = 200

        // Handle drag & tap for audio toggle
        imageView.setOnTouchListener(object : View.OnTouchListener {
            private var downTime: Long = 0

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        downTime = System.currentTimeMillis()
                        initialX = params.x
                        initialY = params.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = (event.rawX - initialTouchX).toInt()
                        val dy = (event.rawY - initialTouchY).toInt()
                        params.x = initialX - dx  // drag in x
                        params.y = initialY + dy  // drag in y
                        try {
                            windowManager?.updateViewLayout(
                                bubbleView,
                                params
                            )
                        } catch (_: Throwable) {
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        val upTime = System.currentTimeMillis()
                        val elapsed = upTime - downTime
                        val movedX = Math.abs(event.rawX - initialTouchX)
                        val movedY = Math.abs(event.rawY - initialTouchY)

                        // Treat as click if movement small and short press
                        if (elapsed < 200 && movedX < 10 && movedY < 10) {
                            toggleAudio()
                        }
                        return true
                    }
                }
                return false
            }
        })

        bubbleView = imageView
        windowManager?.addView(bubbleView, params)
    }

    private fun toggleAudio() {
        val am = audioManager ?: return
        isMuted = !isMuted

        try {
            val stream = AudioManager.STREAM_MUSIC
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.adjustStreamVolume(
                    stream,
                    if (isMuted) AudioManager.ADJUST_MUTE
                    else AudioManager.ADJUST_UNMUTE,
                    0
                )
            } else {
                @Suppress("DEPRECATION")
                am.setStreamMute(stream, isMuted)
            }
        } catch (_: Throwable) {
        }

        // Optional: you could also change alpha or tint based on mute state
        val img = bubbleView as? ImageView
        img?.alpha = if (isMuted) 0.3f else 0.5f
    }

    private fun hideBubble() {
        if (bubbleView != null) {
            try {
                windowManager?.removeView(bubbleView)
            } catch (_: Throwable) {
            }
            bubbleView = null
        }
    }

    override fun onDestroy() {
        hideBubble()
        super.onDestroy()
    }
}

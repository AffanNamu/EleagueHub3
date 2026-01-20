package com.eleaguehub.app

import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
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

    override fun onBind(intent: Intent?): IBinder? = null

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

      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
          !Settings.canDrawOverlays(this)
      ) {
          return
      }

      windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

      val size = (48 * resources.displayMetrics.density).toInt()

      val imageView = ImageView(this).apply {
          setImageResource(android.R.drawable.ic_btn_speak_now)
          alpha = 0.8f
          setOnClickListener {
              // Bring app to foreground
              val intent = Intent(this@LiveOverlayBubbleService, MainActivity::class.java)
              intent.addFlags(
                  Intent.FLAG_ACTIVITY_NEW_TASK or
                          Intent.FLAG_ACTIVITY_SINGLE_TOP or
                          Intent.FLAG_ACTIVITY_CLEAR_TOP
              )
              ContextCompat.startActivity(
                  this@LiveOverlayBubbleService,
                  intent,
                  null
              )
          }
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

      params.gravity = Gravity.TOP or Gravity.END
      params.x = 20
      params.y = 200

      bubbleView = imageView
      windowManager?.addView(bubbleView, params)
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

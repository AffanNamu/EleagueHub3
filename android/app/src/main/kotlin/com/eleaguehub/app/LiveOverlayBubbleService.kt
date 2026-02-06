package com.eleaguehub.app

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

class LiveOverlayBubbleService : Service() {

    companion object {
        const val ACTION_SHOW = "com.eleaguehub.app.LIVE_OVERLAY_SHOW"
        const val ACTION_HIDE = "com.eleaguehub.app.LIVE_OVERLAY_HIDE"

        private const val DART_CHANNEL = "local_live"
        private const val DART_METHOD = "overlayAction"
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    private var windowManager: WindowManager? = null
    private var rootView: View? = null

    // drag state
    private var initialX: Int = 0
    private var initialY: Int = 0
    private var initialTouchX: Float = 0f
    private var initialTouchY: Float = 0f

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> showOverlay()
            ACTION_HIDE -> {
                hideOverlay()
                stopSelf()
            }
        }
        return START_STICKY
    }

    private fun showOverlay() {
        if (rootView != null) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        val layoutType =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )

        params.gravity = Gravity.TOP or Gravity.END
        params.x = dp(14)
        params.y = dp(170)

        val root = FrameLayout(this)

        // Container: icons row + optional panel below
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(8), dp(8), dp(8))
            background = ContextCompat.getDrawable(this@LiveOverlayBubbleService, android.R.drawable.dialog_holo_light_frame)
            alpha = 0.78f
        }

        val iconRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val mic = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_btn_speak_now)
            alpha = 0.95f
            setPadding(dp(10), dp(10), dp(10), dp(10))
            setOnClickListener {
                sendToDart(action = "toggle_mic")
            }
            setOnLongClickListener {
                expandApp()
                true
            }
        }

        val msg = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_dialog_email)
            alpha = 0.95f
            setPadding(dp(10), dp(10), dp(10), dp(10))
        }

        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            setPadding(0, dp(8), 0, 0)
        }

        fun togglePanel() {
            panel.visibility = if (panel.visibility == View.VISIBLE) View.GONE else View.VISIBLE
        }

        msg.setOnClickListener { togglePanel() }

        // Quick messages (English defaults; Dart side may no-op if no active session)
        val quick = listOf(
            "Focus!",
            "Calm down",
            "We got this",
            "One more goal!",
            "Don’t give up",
            "Sorry",
            "Unlucky",
            "What a goal!",
            "Ref??"
        )

        quick.forEach { label ->
            panel.addView(
                Button(this).apply {
                    text = label
                    isAllCaps = false
                    setOnClickListener {
                        sendToDart(action = "send_quick", label = label)
                        panel.visibility = View.GONE
                    }
                }
            )
        }

        panel.addView(
            LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.END
                setPadding(0, dp(8), 0, 0)

                addView(
                    Button(this@LiveOverlayBubbleService).apply {
                        text = "End"
                        isAllCaps = false
                        setOnClickListener {
                            sendToDart(action = "end")
                            panel.visibility = View.GONE
                        }
                    }
                )
                addView(
                    Button(this@LiveOverlayBubbleService).apply {
                        text = "Expand"
                        isAllCaps = false
                        setOnClickListener {
                            expandApp()
                            panel.visibility = View.GONE
                        }
                    }
                )
                addView(
                    Button(this@LiveOverlayBubbleService).apply {
                        text = "Hide"
                        isAllCaps = false
                        setOnClickListener {
                            hideOverlay()
                            stopSelf()
                        }
                    }
                )
            }
        )

        iconRow.addView(mic)
        iconRow.addView(msg)

        // Drag handle: drag the icon row only.
        iconRow.setOnTouchListener(object : View.OnTouchListener {
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
                        params.x = initialX - dx
                        params.y = initialY + dy
                        try {
                            windowManager?.updateViewLayout(root, params)
                        } catch (_: Throwable) {
                        }
                        return true
                    }

                    MotionEvent.ACTION_UP -> {
                        val elapsed = System.currentTimeMillis() - downTime
                        val movedX = abs(event.rawX - initialTouchX)
                        val movedY = abs(event.rawY - initialTouchY)

                        // Click-through: if user didn't drag, treat like click on row (toggle panel)
                        if (elapsed < 200 && movedX < 10 && movedY < 10) {
                            togglePanel()
                        }
                        return true
                    }
                }
                return false
            }
        })

        container.addView(iconRow)
        container.addView(panel)
        root.addView(container)

        rootView = root

        try {
            windowManager?.addView(rootView, params)
        } catch (_: Throwable) {
            rootView = null
            stopSelf()
        }
    }

    private fun hideOverlay() {
        val v = rootView ?: return
        try {
            windowManager?.removeView(v)
        } catch (_: Throwable) {
        } finally {
            rootView = null
        }
    }

    private fun sendToDart(action: String, label: String? = null) {
        // If engine isn't alive, best-effort: bring app to foreground so Flutter can handle it.
        val messenger = FlutterEngineHolder.messengerOrNull()
        if (messenger == null) {
            expandApp()
            return
        }

        mainHandler.post {
            try {
                val ch = MethodChannel(messenger, DART_CHANNEL)
                val args = HashMap<String, Any?>()
                args["action"] = action
                if (label != null) args["label"] = label
                ch.invokeMethod(DART_METHOD, args)
            } catch (_: Throwable) {
                // fallback: open app
                expandApp()
            }
        }
    }

    private fun expandApp() {
        try {
            val launch = packageManager.getLaunchIntentForPackage(packageName)
            if (launch != null) {
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                startActivity(launch)
            }
        } catch (_: Throwable) {
        }
    }

    private fun dp(v: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            v.toFloat(),
            resources.displayMetrics
        ).toInt()
    }

    override fun onDestroy() {
        hideOverlay()
        super.onDestroy()
    }
}

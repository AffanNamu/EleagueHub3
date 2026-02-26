package com.eleaguehub.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.PixelFormat
import android.graphics.Point
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import kotlin.math.abs
import kotlin.math.max

class LiveOverlayBubbleService : Service() {

    companion object {
        const val ACTION_SHOW = "com.eleaguehub.app.LIVE_OVERLAY_SHOW"
        const val ACTION_HIDE = "com.eleaguehub.app.LIVE_OVERLAY_HIDE"

        // Sent from MainActivity after quick messages / mic state update.
        const val ACTION_REFRESH = "com.eleaguehub.app.LIVE_OVERLAY_REFRESH"

        private const val DART_CHANNEL = "local_live"
        private const val DART_METHOD = "overlayAction"

        // SharedPreferences used by OverlayPositionStore + quick messages + mic state.
        private const val OVERLAY_PREFS = "overlay_prefs"
        private const val KEY_QUICK_MESSAGES_JSON = "quick_messages_json"
        private const val KEY_MIC_MUTED = "mic_muted"

        // Foreground service (Android 8+) to avoid background service start restrictions
        // and improve overlay stability across OEMs.
        private const val FGS_CHANNEL_ID = "overlay_bubble"
        private const val FGS_CHANNEL_NAME = "Overlay"
        private const val FGS_NOTIF_ID = 5151
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    private var windowManager: WindowManager? = null
    private var params: WindowManager.LayoutParams? = null
    private var rootView: View? = null

    private lateinit var positionStore: OverlayPositionStore
    private var touchSlop: Int = 10
    private val marginPx by lazy { dp(8) }

    // UI refs (so we can refresh list/state without rebuilding whole overlay)
    private var panelView: LinearLayout? = null
    private var stackView: LinearLayout? = null
    private var micView: ImageView? = null

    private var foregroundStarted: Boolean = false

    private val configReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != Intent.ACTION_CONFIGURATION_CHANGED) return
            rootView?.post { applyStoredPositionAndClamp() }
        }
    }

    override fun onCreate() {
        super.onCreate()
        positionStore = OverlayPositionStore(this)
        touchSlop = ViewConfiguration.get(this).scaledTouchSlop.coerceAtLeast(8)

        // Android 13+ requires explicit exported-ness when dynamically registering receivers.
        try {
            val filter = IntentFilter(Intent.ACTION_CONFIGURATION_CHANGED)
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(configReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(configReceiver, filter)
            }
        } catch (_: Throwable) {
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> {
                // Must be foreground on Android 8+ when started via startForegroundService()
                ensureForegroundIfNeeded()
                showOverlay()
            }

            ACTION_REFRESH -> refreshOverlayUi()

            ACTION_HIDE -> {
                hideOverlay()
                stopForegroundCompat()
                stopSelf()
            }
        }
        return START_STICKY
    }

    private fun ensureForegroundIfNeeded() {
        if (foregroundStarted) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        try {
            createFgsChannelIfNeeded()
            val n = buildFgsNotification()
            startForeground(FGS_NOTIF_ID, n)
            foregroundStarted = true
        } catch (_: Throwable) {
            // If we cannot become foreground (rare OEM/permission edge cases),
            // stop to avoid "Service did not call startForeground()" crash when started as FGS.
            try {
                stopSelf()
            } catch (_: Throwable) {
            }
        }
    }

    private fun buildFgsNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = if (launchIntent != null) {
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
            PendingIntent.getActivity(this, 0, launchIntent, flags)
        } else null

        val hideIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, LiveOverlayBubbleService::class.java).apply { action = ACTION_HIDE },
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        val b = NotificationCompat.Builder(this, FGS_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Overlay active")
            .setContentText("Tap to return to eSportly")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .addAction(NotificationCompat.Action(0, "Hide", hideIntent))

        if (contentIntent != null) b.setContentIntent(contentIntent)
        return b.build()
    }

    private fun createFgsChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(FGS_CHANNEL_ID) != null) return

        val ch = NotificationChannel(FGS_CHANNEL_ID, FGS_CHANNEL_NAME, NotificationManager.IMPORTANCE_MIN)
        ch.description = "Keeps the overlay running reliably"
        nm.createNotificationChannel(ch)
    }

    private fun stopForegroundCompat() {
        if (!foregroundStarted) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Throwable) {
        } finally {
            foregroundStarted = false
        }
    }

    private fun showOverlay() {
        if (rootView != null) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            stopForegroundCompat()
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

        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )

        // Use TOP|START so x/y are consistent and easier to persist/clamp.
        lp.gravity = Gravity.TOP or Gravity.START

        val root = FrameLayout(this)

        // Vertical stack: pill row + panel
        val stack = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        stackView = stack

        val pill = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(8), dp(8), dp(8))
            alpha = 0.92f
            isClickable = true
            isFocusable = false
            background = GradientDrawable().apply {
                cornerRadius = dp(22).toFloat()
                setColor(0xCC0B1220.toInt())
                setStroke(dp(1), 0x33FFFFFF)
            }
        }

        val mic = ImageView(this).apply {
            alpha = 0.98f
            setPadding(dp(10), dp(10), dp(10), dp(10))
            setColorFilter(ContextCompat.getColor(this@LiveOverlayBubbleService, android.R.color.white))
            isClickable = true
            contentDescription = "Voice"
            setOnClickListener {
                // Action is handled in Flutter; Flutter will push real mic state back via setOverlayMicMutedState().
                sendToDart(action = "toggle_mic")
            }
            setOnLongClickListener {
                expandApp()
                true
            }
        }
        micView = mic

        val msg = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_dialog_email)
            alpha = 0.98f
            setPadding(dp(10), dp(10), dp(10), dp(10))
            setColorFilter(ContextCompat.getColor(this@LiveOverlayBubbleService, android.R.color.white))
            isClickable = true
            contentDescription = "Messages"
        }

        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            setPadding(dp(8), dp(10), dp(8), dp(8))
            background = GradientDrawable().apply {
                cornerRadius = dp(16).toFloat()
                setColor(0xCC0B1220.toInt())
                setStroke(dp(1), 0x33FFFFFF)
            }
        }
        panelView = panel

        fun togglePanel() {
            panel.visibility = if (panel.visibility == View.VISIBLE) View.GONE else View.VISIBLE
            root.post { clampToScreenAndUpdate(saveAfter = false) }
        }

        msg.setOnClickListener { togglePanel() }

        pill.addView(mic)
        pill.addView(msg)

        // Drag: drag by touching pill or icons.
        val dragListener = DragTouchListener(onDragEnd = { snapToEdgeAndSave() })
        pill.setOnTouchListener(dragListener)
        mic.setOnTouchListener(dragListener)
        msg.setOnTouchListener(dragListener)

        stack.addView(pill)
        stack.addView(panel)

        root.addView(stack)

        rootView = root
        params = lp

        // Populate UI now
        rebuildPanelContents()
        applyMicVisual()

        // Measure and apply stored position
        measureView(root)
        applyStoredPositionAndClamp()

        try {
            windowManager?.addView(rootView, params)
        } catch (_: Throwable) {
            rootView = null
            params = null
            panelView = null
            stackView = null
            micView = null
            stopForegroundCompat()
            stopSelf()
        }
    }

    private fun refreshOverlayUi() {
        if (rootView == null) return
        rebuildPanelContents()
        applyMicVisual()
        rootView?.post {
            measureView(rootView!!)
            clampToScreenAndUpdate(saveAfter = false)
        }
    }

    private fun rebuildPanelContents() {
        val panel = panelView ?: return
        panel.removeAllViews()

        val messages = loadQuickMessages()

        for (label in messages) {
            panel.addView(
                Button(this).apply {
                    text = label
                    isAllCaps = false
                    setOnClickListener {
                        sendToDart(action = "send_quick", label = label)
                        panel.visibility = View.GONE
                        rootView?.post { clampToScreenAndUpdate(saveAfter = false) }
                    }
                }
            )
        }

        // Action row
        panel.addView(
            LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.END
                setPadding(0, dp(10), 0, 0)

                addView(
                    Button(this@LiveOverlayBubbleService).apply {
                        text = "End"
                        isAllCaps = false
                        setOnClickListener {
                            sendToDart(action = "end")
                            panel.visibility = View.GONE
                            rootView?.post { clampToScreenAndUpdate(saveAfter = false) }
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
                            rootView?.post { clampToScreenAndUpdate(saveAfter = false) }
                        }
                    }
                )
                addView(
                    Button(this@LiveOverlayBubbleService).apply {
                        text = "Hide"
                        isAllCaps = false
                        setOnClickListener {
                            hideOverlay()
                            stopForegroundCompat()
                            stopSelf()
                        }
                    }
                )
            }
        )
    }

    private fun loadQuickMessages(): List<String> {
        // Defaults are always available.
        val defaults = listOf(
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

        try {
            val sp = applicationContext.getSharedPreferences(OVERLAY_PREFS, Context.MODE_PRIVATE)
            val raw = sp.getString(KEY_QUICK_MESSAGES_JSON, null) ?: return defaults

            val arr = JSONArray(raw)
            val out = ArrayList<String>(arr.length())
            for (i in 0 until arr.length()) {
                val s = arr.optString(i, "").trim()
                if (s.isNotEmpty()) out.add(s)
            }

            // If Flutter sent something, use it (already combined defaults+custom).
            return if (out.isNotEmpty()) out else defaults
        } catch (_: Throwable) {
            return defaults
        }
    }

    private fun loadMicMuted(): Boolean {
        return try {
            val sp = applicationContext.getSharedPreferences(OVERLAY_PREFS, Context.MODE_PRIVATE)
            sp.getBoolean(KEY_MIC_MUTED, true) // default muted for safety
        } catch (_: Throwable) {
            true
        }
    }

    private fun applyMicVisual() {
        val mic = micView ?: return
        val muted = loadMicMuted()

        if (muted) {
            mic.setImageResource(android.R.drawable.ic_lock_silent_mode)
            mic.alpha = 0.75f
        } else {
            mic.setImageResource(android.R.drawable.ic_btn_speak_now)
            mic.alpha = 0.98f
        }
    }

    private inner class DragTouchListener(
        private val onDragEnd: () -> Unit
    ) : View.OnTouchListener {

        private var dragging = false
        private var downRawX = 0f
        private var downRawY = 0f
        private var startX = 0
        private var startY = 0

        override fun onTouch(v: View, event: MotionEvent): Boolean {
            val lp = params ?: return false

            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    dragging = false
                    downRawX = event.rawX
                    downRawY = event.rawY
                    startX = lp.x
                    startY = lp.y
                    return true
                }

                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downRawX
                    val dy = event.rawY - downRawY

                    if (!dragging) {
                        if (abs(dx) > touchSlop || abs(dy) > touchSlop) {
                            dragging = true
                        } else {
                            return true
                        }
                    }

                    lp.x = startX + dx.toInt()
                    lp.y = startY + dy.toInt()
                    clampToScreenAndUpdate(saveAfter = false)
                    return true
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (dragging) {
                        onDragEnd()
                        return true
                    }

                    // Not a drag: let click handlers run.
                    v.performClick()
                    return true
                }
            }

            return false
        }
    }

    private fun measureView(v: View) {
        try {
            val wSpec = View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
            val hSpec = View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
            v.measure(wSpec, hSpec)
        } catch (_: Throwable) {
        }
    }

    private fun screenSizePx(): Pair<Int, Int> {
        val wm = windowManager ?: return Pair(resources.displayMetrics.widthPixels, resources.displayMetrics.heightPixels)

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = wm.currentWindowMetrics.bounds
            Pair(max(1, bounds.width()), max(1, bounds.height()))
        } else {
            @Suppress("DEPRECATION")
            val display = wm.defaultDisplay
            val p = Point()
            @Suppress("DEPRECATION")
            display.getSize(p)
            Pair(max(1, p.x), max(1, p.y))
        }
    }

    private fun applyStoredPositionAndClamp() {
        val lp = params ?: return
        val v = rootView ?: return

        measureView(v)

        val (screenW, screenH) = screenSizePx()
        val viewW = if (v.measuredWidth > 0) v.measuredWidth else dp(120)
        val viewH = if (v.measuredHeight > 0) v.measuredHeight else dp(56)

        val (xf, yf) = positionStore.load()
        val (xPx, yPx) = positionStore.fracToPx(
            xFrac = xf,
            yFrac = yf,
            screenW = screenW,
            screenH = screenH,
            viewW = viewW,
            viewH = viewH,
            marginPx = marginPx
        )

        lp.x = xPx
        lp.y = yPx

        try {
            windowManager?.updateViewLayout(v, lp)
        } catch (_: Throwable) {
        }
    }

    private fun clampToScreenAndUpdate(saveAfter: Boolean) {
        val lp = params ?: return
        val v = rootView ?: return

        val (screenW, screenH) = screenSizePx()
        val viewW = if (v.width > 0) v.width else (if (v.measuredWidth > 0) v.measuredWidth else dp(120))
        val viewH = if (v.height > 0) v.height else (if (v.measuredHeight > 0) v.measuredHeight else dp(56))

        val maxX = max(0, screenW - viewW - marginPx)
        val maxY = max(0, screenH - viewH - marginPx)

        lp.x = lp.x.coerceIn(0, maxX)
        lp.y = lp.y.coerceIn(0, maxY)

        try {
            windowManager?.updateViewLayout(v, lp)
        } catch (_: Throwable) {
        }

        if (saveAfter) {
            val (xf, yf) = positionStore.pxToFrac(
                xPx = lp.x,
                yPx = lp.y,
                screenW = screenW,
                screenH = screenH,
                viewW = viewW,
                viewH = viewH,
                marginPx = marginPx
            )
            positionStore.save(xf, yf)
        }
    }

    private fun snapToEdgeAndSave() {
        val lp = params ?: return
        val v = rootView ?: return

        measureView(v)

        val (screenW, _) = screenSizePx()
        val viewW = if (v.width > 0) v.width else (if (v.measuredWidth > 0) v.measuredWidth else dp(120))

        lp.x = positionStore.snapToEdge(lp.x, screenW, viewW, marginPx)
        clampToScreenAndUpdate(saveAfter = true)
    }

    private fun hideOverlay() {
        val v = rootView ?: return
        try {
            windowManager?.removeView(v)
        } catch (_: Throwable) {
        } finally {
            rootView = null
            params = null
            panelView = null
            stackView = null
            micView = null
        }
    }

    private fun sendToDart(action: String, label: String? = null) {
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
        try {
            unregisterReceiver(configReceiver)
        } catch (_: Throwable) {
        }
        hideOverlay()
        stopForegroundCompat()
        super.onDestroy()
    }
}

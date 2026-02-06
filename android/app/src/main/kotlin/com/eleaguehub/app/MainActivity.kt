package com.eleaguehub.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

private const val LOCAL_LIVE_CHANNEL = "local_live"

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Expose messenger to Services (overlay/foreground) so they can send actions to Dart.
        FlutterEngineHolder.setBinaryMessenger(flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LOCAL_LIVE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                // Foreground streaming service controls (existing)
                "startForegroundStreamingService" -> {
                    val title = call.argument<String>("title") ?: "Live streaming"
                    val text = call.argument<String>("text") ?: "Broadcasting is running"

                    try {
                        val intent = Intent(this, LocalLiveForegroundService::class.java).apply {
                            action = LocalLiveForegroundService.ACTION_START
                            putExtra(LocalLiveForegroundService.EXTRA_TITLE, title)
                            putExtra(LocalLiveForegroundService.EXTRA_TEXT, text)
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            ContextCompat.startForegroundService(this, intent)
                        } else {
                            startService(intent)
                        }

                        result.success(null)
                    } catch (e: Throwable) {
                        result.error("FG_START_FAILED", e.toString(), null)
                    }
                }

                "stopForegroundStreamingService" -> {
                    try {
                        val intent = Intent(this, LocalLiveForegroundService::class.java).apply {
                            action = LocalLiveForegroundService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(null)
                    } catch (e: Throwable) {
                        result.error("FG_STOP_FAILED", e.toString(), null)
                    }
                }

                // Battery optimization helpers (existing)
                "openBatteryOptimizationSettings" -> {
                    try {
                        val i = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        result.success(null)
                    } catch (e: Throwable) {
                        result.error("OPEN_BATT_SETTINGS_FAILED", e.toString(), null)
                    }
                }

                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        val pkg = packageName
                        val i = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                        i.data = Uri.parse("package:$pkg")
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        result.success(null)
                    } catch (e: Throwable) {
                        result.error("REQUEST_IGNORE_BATT_FAILED", e.toString(), null)
                    }
                }

                "openAppDetailsSettings" -> {
                    try {
                        val i = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        i.data = Uri.parse("package:$packageName")
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        result.success(null)
                    } catch (e: Throwable) {
                        result.error("OPEN_APP_DETAILS_FAILED", e.toString(), null)
                    }
                }

                "getDeviceInfo" -> {
                    val map = hashMapOf<String, Any?>(
                        "manufacturer" to (Build.MANUFACTURER ?: ""),
                        "brand" to (Build.BRAND ?: ""),
                        "model" to (Build.MODEL ?: ""),
                        "sdkInt" to Build.VERSION.SDK_INT
                    )
                    result.success(map)
                }

                // Overlay permission + bubble (existing)
                "isOverlayPermissionGranted" -> {
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    result.success(granted)
                }

                "requestOverlayPermission" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                        result.success(null)
                    } catch (e: Throwable) {
                        result.error("OVERLAY_REQUEST_FAILED", e.toString(), null)
                    }
                }

                "startLiveOverlayBubble" -> {
                    try {
                        val intent = Intent(this, LiveOverlayBubbleService::class.java).apply {
                            action = LiveOverlayBubbleService.ACTION_SHOW
                        }
                        startService(intent)
                        result.success(null)
                    } catch (e: Throwable) {
                        result.error("OVERLAY_START_FAILED", e.toString(), null)
                    }
                }

                "stopLiveOverlayBubble" -> {
                    try {
                        val intent = Intent(this, LiveOverlayBubbleService::class.java).apply {
                            action = LiveOverlayBubbleService.ACTION_HIDE
                        }
                        startService(intent)
                        result.success(null)
                    } catch (e: Throwable) {
                        result.error("OVERLAY_STOP_FAILED", e.toString(), null)
                    }
                }

                // New: store quick messages for overlay (defaults + premium custom from Flutter)
                "setOverlayQuickMessages" -> {
                    try {
                        val raw = call.arguments
                        val list = mutableListOf<String>()

                        if (raw is List<*>) {
                            for (e in raw) {
                                val s = (e ?: "").toString().trim()
                                if (s.isNotEmpty()) list.add(s)
                            }
                        }

                        val arr = JSONArray()
                        for (s in list) arr.put(s)

                        val sp = applicationContext.getSharedPreferences("overlay_prefs", Context.MODE_PRIVATE)
                        sp.edit().putString("quick_messages_json", arr.toString()).apply()

                        // Ask overlay to refresh if it's already running.
                        try {
                            val i = Intent(this, LiveOverlayBubbleService::class.java).apply {
                                action = LiveOverlayBubbleService.ACTION_REFRESH
                            }
                            startService(i)
                        } catch (_: Throwable) {
                        }

                        result.success(null)
                    } catch (e: Throwable) {
                        result.error("SET_OVERLAY_QUICK_FAILED", e.toString(), null)
                    }
                }

                // New: store mic muted state for overlay icon visual
                "setOverlayMicMutedState" -> {
                    try {
                        var muted = false
                        val raw = call.arguments
                        if (raw is Boolean) {
                            muted = raw
                        } else if (raw is Map<*, *>) {
                            val v = raw["muted"]
                            if (v is Boolean) muted = v
                        } else {
                            val v = call.argument<Boolean>("muted")
                            if (v != null) muted = v
                        }

                        val sp = applicationContext.getSharedPreferences("overlay_prefs", Context.MODE_PRIVATE)
                        sp.edit().putBoolean("mic_muted", muted).apply()

                        // Ask overlay to refresh if it's already running.
                        try {
                            val i = Intent(this, LiveOverlayBubbleService::class.java).apply {
                                action = LiveOverlayBubbleService.ACTION_REFRESH
                            }
                            startService(i)
                        } catch (_: Throwable) {
                        }

                        result.success(null)
                    } catch (e: Throwable) {
                        result.error("SET_OVERLAY_MIC_STATE_FAILED", e.toString(), null)
                    }
                }

                // New aliases (for global overlay UX from HomeShell/Settings)
                "startGlobalOverlay" -> {
                    try {
                        val intent = Intent(this, LiveOverlayBubbleService::class.java).apply {
                            action = LiveOverlayBubbleService.ACTION_SHOW
                        }
                        startService(intent)
                        result.success(null)
                    } catch (e: Throwable) {
                        result.error("GLOBAL_OVERLAY_START_FAILED", e.toString(), null)
                    }
                }

                "stopGlobalOverlay" -> {
                    try {
                        val intent = Intent(this, LiveOverlayBubbleService::class.java).apply {
                            action = LiveOverlayBubbleService.ACTION_HIDE
                        }
                        startService(intent)
                        result.success(null)
                    } catch (e: Throwable) {
                        result.error("GLOBAL_OVERLAY_STOP_FAILED", e.toString(), null)
                    }
                }

                // Voice-call style FGS controls
                "startOverlayVoiceForegroundService" -> {
                    val title = call.argument<String>("title") ?: "Voice chat"
                    val text = call.argument<String>("text") ?: "Voice chat is running"
                    try {
                        val intent = Intent().apply {
                            setClassName(this@MainActivity, "com.eleaguehub.app.OverlayVoiceForegroundService")
                            action = "com.eleaguehub.app.OVERLAY_VOICE_FGS_START"
                            putExtra("title", title)
                            putExtra("text", text)
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            ContextCompat.startForegroundService(this, intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    } catch (e: Throwable) {
                        result.error("VOICE_FGS_START_FAILED", e.toString(), null)
                    }
                }

                "stopOverlayVoiceForegroundService" -> {
                    try {
                        val intent = Intent().apply {
                            setClassName(this@MainActivity, "com.eleaguehub.app.OverlayVoiceForegroundService")
                            action = "com.eleaguehub.app.OVERLAY_VOICE_FGS_STOP"
                        }
                        startService(intent)
                        result.success(null)
                    } catch (e: Throwable) {
                        result.error("VOICE_FGS_STOP_FAILED", e.toString(), null)
                    }
                }

                // Old placeholders (existing; not used now; handled in Dart/WebRTC)
                "startHostSession" -> {
                    Log.i("LocalLive", "startHostSession (unused now; handled in Dart/WebRTC)")
                    result.success(null)
                }
                "stopHostSession" -> {
                    Log.i("LocalLive", "stopHostSession (unused now; handled in Dart/WebRTC)")
                    result.success(null)
                }
                "joinViewerSession" -> {
                    Log.i("LocalLive", "joinViewerSession (unused now; handled in Dart/WebRTC)")
                    result.success(null)
                }
                "leaveViewerSession" -> {
                    Log.i("LocalLive", "leaveViewerSession (unused now; handled in Dart/WebRTC)")
                    result.success(null)
                }
                "sendLiveEvent" -> {
                    Log.i("LocalLive", "sendLiveEvent (unused now; handled in Dart/WebRTC data channel)")
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }
}

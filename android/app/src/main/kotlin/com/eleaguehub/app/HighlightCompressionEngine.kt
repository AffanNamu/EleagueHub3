package com.eleaguehub.app

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.TransformationRequest
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.min

/**
 * Highlights compression engine (Android-only) using AndroidX Media3 Transformer.
 *
 * Why:
 * - CI cannot reach maven.arthenica.com, so ffmpeg-kit builds fail.
 * - Media3 is hosted on MavenCentral/Google -> reliable.
 *
 * Contract:
 * - MethodChannel: "highlight_compression"
 *   - probe { inputPath } -> { durationSeconds, width, height, format }
 *   - compress { taskId, inputPath, outputPath, maxHeight, videoBitrateKbps, audioBitrateKbps }
 *       -> { outputPath, outputBytes, usedMaxHeight, usedVideoBitrateKbps, usedAudioBitrateKbps }
 *
 * - EventChannel: "highlight_compression_progress"
 *   emits { taskId, progress01 } best-effort.
 */
object HighlightCompressionEngine {

    private const val METHOD_CHANNEL = "highlight_compression"
    private const val PROGRESS_CHANNEL = "highlight_compression_progress"

    private val mainHandler = Handler(Looper.getMainLooper())

    private var progressSink: EventChannel.EventSink? = null

    // Keep single active compression to avoid complexity and cost.
    private val busy = AtomicBoolean(false)
    private var activeTaskId: String? = null
    private var activeTransformer: Transformer? = null

    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "probe" -> {
                        val inputPath = call.argument<String>("inputPath") ?: ""
                        if (inputPath.trim().isEmpty()) {
                            result.error("BAD_ARGS", "inputPath is required", null)
                            return@setMethodCallHandler
                        }

                        val info = probe(context, inputPath.trim())
                        result.success(
                            hashMapOf<String, Any?>(
                                "durationSeconds" to info.durationSeconds,
                                "width" to info.width,
                                "height" to info.height,
                                "format" to info.format
                            )
                        )
                    }

                    "compress" -> {
                        handleCompress(context, call, result)
                    }

                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                result.error("NATIVE_ERROR", t.toString(), null)
            }
        }

        EventChannel(messenger, PROGRESS_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                progressSink = events
            }

            override fun onCancel(arguments: Any?) {
                progressSink = null
            }
        })
    }

    private data class Probe(
        val durationSeconds: Double,
        val width: Int,
        val height: Int,
        val format: String?
    )

    private fun toUri(inputPath: String): Uri {
        val s = inputPath.trim()
        return when {
            s.startsWith("content://") -> Uri.parse(s)
            s.startsWith("file://") -> Uri.parse(s)
            else -> Uri.fromFile(File(s))
        }
    }

    private fun probe(context: Context, inputPath: String): Probe {
        val uri = toUri(inputPath)

        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(context, uri)
            val durMs = (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION) ?: "0").toLongOrNull() ?: 0L
            val w = (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH) ?: "0").toIntOrNull() ?: 0
            val h = (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT) ?: "0").toIntOrNull() ?: 0
            val mime = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE)

            return Probe(
                durationSeconds = max(0.0, durMs.toDouble() / 1000.0),
                width = max(0, w),
                height = max(0, h),
                format = mime?.trim()?.ifEmpty { null }
            )
        } finally {
            try { r.release() } catch (_: Throwable) {}
        }
    }

    private fun emitProgress(taskId: String, progress01: Double) {
        val sink = progressSink ?: return
        val p = progress01.coerceIn(0.0, 1.0)

        // Ensure event is emitted on main thread.
        mainHandler.post {
            try {
                sink.success(
                    hashMapOf<String, Any?>(
                        "taskId" to taskId,
                        "progress01" to p
                    )
                )
            } catch (_: Throwable) {
            }
        }
    }

    private fun handleCompress(context: Context, call: MethodCall, result: MethodChannel.Result) {
        if (!busy.compareAndSet(false, true)) {
            result.error("BUSY", "Compression is already running.", null)
            return
        }

        val taskId = (call.argument<String>("taskId") ?: "").trim()
        val inputPath = (call.argument<String>("inputPath") ?: "").trim()
        val outputPath = (call.argument<String>("outputPath") ?: "").trim()

        val maxHeight = (call.argument<Number>("maxHeight") ?: 720).toInt()
        val videoKbps = (call.argument<Number>("videoBitrateKbps") ?: 1500).toInt()
        val audioKbps = (call.argument<Number>("audioBitrateKbps") ?: 128).toInt()

        if (taskId.isEmpty() || inputPath.isEmpty() || outputPath.isEmpty()) {
            busy.set(false)
            result.error("BAD_ARGS", "taskId, inputPath, outputPath are required", null)
            return
        }

        activeTaskId = taskId
        emitProgress(taskId, 0.0)

        try {
            // Ensure output directory exists.
            val outFile = File(outputPath)
            outFile.parentFile?.mkdirs()

            // Probe to compute a safe scale factor.
            val inInfo = probe(context, inputPath)
            val inH = max(0, inInfo.height)
            val targetH = max(240, min(maxHeight, 720))
            val scale = if (inH <= 0) 1.0 else min(1.0, targetH.toDouble() / inH.toDouble())

            val mediaItem = MediaItem.fromUri(toUri(inputPath))

            val transformationRequest = TransformationRequest.Builder()
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .build()

            val videoEffect = ScaleAndRotateTransformation.Builder()
                .setScale(scale.toFloat(), scale.toFloat())
                .build()

            val editedMediaItem = EditedMediaItem.Builder(mediaItem)
                .setEffects(Effects(emptyList(), listOf(videoEffect)))
                .build()

            // Encoder settings (best-effort). Not all devices honor bitrate precisely.
            val encoderFactory = try {
                val bpsV = max(100_000, videoKbps * 1000)
                val bpsA = max(64_000, audioKbps * 1000)

                // DefaultEncoderFactory has evolved; keep this minimal and defensive.
                DefaultEncoderFactory.Builder(context)
                    .setRequestedVideoEncoderSettings(
                        androidx.media3.transformer.VideoEncoderSettings.Builder()
                            .setBitrate(bpsV)
                            .build()
                    )
                    .setRequestedAudioEncoderSettings(
                        androidx.media3.transformer.AudioEncoderSettings.Builder()
                            .setBitrate(bpsA)
                            .build()
                    )
                    .build()
            } catch (_: Throwable) {
                null
            }

            val listener = object : Transformer.Listener {
                override fun onCompleted(composition: androidx.media3.transformer.Composition, exportResult: ExportResult) {
                    cleanupAfterFinish()

                    try {
                        val bytes = outFile.length().toInt()
                        emitProgress(taskId, 1.0)
                        result.success(
                            hashMapOf<String, Any?>(
                                "outputPath" to outputPath,
                                "outputBytes" to bytes,
                                "usedMaxHeight" to targetH,
                                "usedVideoBitrateKbps" to videoKbps,
                                "usedAudioBitrateKbps" to audioKbps
                            )
                        )
                    } catch (t: Throwable) {
                        result.error("OUTPUT_ERROR", t.toString(), null)
                    }
                }

                override fun onError(
                    composition: androidx.media3.transformer.Composition,
                    exportResult: ExportResult,
                    exportException: ExportException
                ) {
                    cleanupAfterFinish()

                    try {
                        if (outFile.exists()) outFile.delete()
                    } catch (_: Throwable) {
                    }

                    result.error("COMPRESS_FAILED", exportException.toString(), null)
                }
            }

            val builder = Transformer.Builder(context)
                .setTransformationRequest(transformationRequest)
                .addListener(listener)

            if (encoderFactory != null) {
                builder.setEncoderFactory(encoderFactory)
            }

            val transformer = builder.build()
            activeTransformer = transformer

            // Start progress polling (best-effort).
            startProgressPolling(taskId, transformer)

            transformer.start(editedMediaItem, outputPath)
        } catch (t: Throwable) {
            cleanupAfterFinish()
            try {
                val outFile = File(outputPath)
                if (outFile.exists()) outFile.delete()
            } catch (_: Throwable) {
            }
            result.error("COMPRESS_FAILED", t.toString(), null)
        }
    }

    private fun startProgressPolling(taskId: String, transformer: Transformer) {
        val running = AtomicBoolean(true)

        fun poll() {
            val curTask = activeTaskId
            if (!running.get() || curTask == null || curTask != taskId) return

            try {
                val holder = ProgressHolder()
                val state = transformer.getProgress(holder)
                // PROGRESS_STATE_AVAILABLE = 1 in Media3, but we don't rely on exact numbers.
                // If progress is available, holder.progress is 0..100.
                val p = holder.progress.toDouble() / 100.0
                if (p.isFinite() && p > 0) emitProgress(taskId, p)
            } catch (_: Throwable) {
                // ignore
            }

            // Continue until completion handler clears task id.
            mainHandler.postDelayed({ poll() }, 450)
        }

        mainHandler.postDelayed({ poll() }, 350)
    }

    private fun cleanupAfterFinish() {
        activeTransformer = null
        activeTaskId = null
        busy.set(false)
    }
}

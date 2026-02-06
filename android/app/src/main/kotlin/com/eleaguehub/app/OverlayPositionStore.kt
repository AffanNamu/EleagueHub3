package com.eleaguehub.app

import android.content.Context
import android.content.SharedPreferences
import kotlin.math.max

/**
 * Summary:
 * - Stores overlay position as fractions of available screen space (0..1).
 * - Rotation-friendly: keeps similar position after portrait/landscape change.
 *
 * Prefs file: overlay_prefs (shared with overlay quick-messages storage).
 */
class OverlayPositionStore(context: Context) {

    companion object {
        private const val PREFS = "overlay_prefs"
        private const val K_X_FRAC = "x_frac"
        private const val K_Y_FRAC = "y_frac"

        // Default: near top-right-ish
        private const val DEFAULT_X_FRAC = 0.88f
        private const val DEFAULT_Y_FRAC = 0.18f
    }

    private val sp: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(): Pair<Float, Float> {
        val x = sp.getFloat(K_X_FRAC, DEFAULT_X_FRAC).coerceIn(0f, 1f)
        val y = sp.getFloat(K_Y_FRAC, DEFAULT_Y_FRAC).coerceIn(0f, 1f)
        return Pair(x, y)
    }

    fun save(xFrac: Float, yFrac: Float) {
        sp.edit()
            .putFloat(K_X_FRAC, xFrac.coerceIn(0f, 1f))
            .putFloat(K_Y_FRAC, yFrac.coerceIn(0f, 1f))
            .apply()
    }

    fun fracToPx(
        xFrac: Float,
        yFrac: Float,
        screenW: Int,
        screenH: Int,
        viewW: Int,
        viewH: Int,
        marginPx: Int
    ): Pair<Int, Int> {
        val maxX = max(0, screenW - viewW - marginPx)
        val maxY = max(0, screenH - viewH - marginPx)

        val x = (xFrac.coerceIn(0f, 1f) * maxX).toInt()
        val y = (yFrac.coerceIn(0f, 1f) * maxY).toInt()

        return Pair(
            x.coerceIn(0, maxX),
            y.coerceIn(0, maxY)
        )
    }

    fun pxToFrac(
        xPx: Int,
        yPx: Int,
        screenW: Int,
        screenH: Int,
        viewW: Int,
        viewH: Int,
        marginPx: Int
    ): Pair<Float, Float> {
        val maxX = max(1, screenW - viewW - marginPx)
        val maxY = max(1, screenH - viewH - marginPx)

        val xf = (xPx.toFloat() / maxX.toFloat()).coerceIn(0f, 1f)
        val yf = (yPx.toFloat() / maxY.toFloat()).coerceIn(0f, 1f)

        return Pair(xf, yf)
    }

    fun snapToEdge(xPx: Int, screenW: Int, viewW: Int, marginPx: Int): Int {
        val maxX = max(0, screenW - viewW - marginPx)
        if (maxX == 0) return 0
        val mid = maxX / 2
        return if (xPx >= mid) maxX else 0
    }
}

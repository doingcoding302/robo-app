package com.robo.app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.os.SystemClock
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.view.ViewConfiguration
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.sin

/**
 * The "Shadow" chibi character, drawn with the Canvas on a 100 x 125 unit grid.
 * Handles idle bobbing, a talking mouth, and the wave / salute / dance actions.
 * Also turns touches into tap, drag and pinch callbacks for the overlay service.
 */
class CharacterView(context: Context) : View(context) {

    var onTap: (() -> Unit)? = null
    var onDrag: ((Float, Float) -> Unit)? = null
    var onGestureEnd: (() -> Unit)? = null
    var onPinch: ((Float) -> Unit)? = null

    companion object {
        private val OUTLINE = Color.parseColor("#06070A")
        private val SKIN = Color.parseColor("#F7DCC6")
        private val DOME = Color.parseColor("#17191F")
        private val BODY = Color.parseColor("#2B3040")
        private val LEG = Color.parseColor("#1C1F29")
        private val BOOT = Color.parseColor("#0F1116")
        private val POD = Color.parseColor("#23262F")
        private val RED = Color.parseColor("#FF2D2D")
        private val MOUTH = Color.parseColor("#4A1D22")
        private val TONGUE = Color.parseColor("#FF8FA3")
    }

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val line = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 2.4f
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
        color = OUTLINE
    }
    private val highlight = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        color = Color.WHITE
    }
    private val glow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 6f
        strokeJoin = Paint.Join.ROUND
        color = RED
    }
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1.4f
        color = RED
    }

    private val rect = RectF()
    private val path = Path()
    private val headPath = Path().apply { addOval(RectF(14f, 16f, 86f, 80f), Path.Direction.CW) }

    // ---------- drawing ----------

    private fun roundRect(c: Canvas, l: Float, t: Float, r: Float, b: Float, radius: Float, color: Int) {
        rect.set(l, t, r, b)
        fill.color = color
        c.drawRoundRect(rect, radius, radius, fill)
        line.strokeWidth = 2.4f
        c.drawRoundRect(rect, radius, radius, line)
    }

    private fun arm(c: Canvas, px: Float, py: Float, a1: Float, a2: Float) {
        c.save()
        c.rotate(a1, px, py)
        roundRect(c, px - 3.4f, py - 2f, px + 3.4f, py + 12f, 3.4f, BODY)
        c.translate(px, py + 11f)
        c.rotate(a2)
        roundRect(c, -3.1f, -2f, 3.1f, 10f, 3.1f, BODY)
        fill.color = RED
        c.drawRect(-3.1f, 6f, 3.1f, 8f, fill)
        fill.color = SKIN
        c.drawCircle(0f, 11f, 3.6f, fill)
        line.strokeWidth = 2.4f
        c.drawCircle(0f, 11f, 3.6f, line)
        c.restore()
    }

    private fun drawMouth(c: Canvas, m: Float) {
        if (m < 0.08f) {
            path.reset()
            path.moveTo(44f, 70f)
            path.quadTo(50f, 74f, 56f, 70f)
            line.strokeWidth = 1.8f
            c.drawPath(path, line)
        } else {
            val h = 3f + 9f * m
            val rx = 6.5f + 1.5f * m
            rect.set(50f - rx, 69f, 50f + rx, 69f + h)
            fill.color = MOUTH
            c.drawOval(rect, fill)
            line.strokeWidth = 1.8f
            c.drawOval(rect, line)
            if (m > 0.4f) {
                rect.set(46f, 69f + h * 0.75f - h * 0.2f, 54f, 69f + h * 0.75f + h * 0.2f)
                fill.color = TONGUE
                c.drawOval(rect, fill)
            }
        }
    }

    override fun onDraw(c: Canvas) {
        super.onDraw(c)
        val t = SystemClock.uptimeMillis() / 1000f
        val action = RoboState.currentAction()
        val speaking = RoboState.speaking

        val bob = sin(t * 2.2f) * 1.4f
        var tilt = 0f
        var hop = 0f
        var a1R = -10f
        var a2R = -8f
        var a1L = 10f
        var a2L = 8f
        when (action) {
            "wave" -> {
                a1R = -135f + 14f * sin(t * 10f)
                a2R = -25f + 18f * sin(t * 10f + 1f)
            }
            "salute" -> {
                a1R = -120f
                a2R = -70f
            }
            "dance" -> {
                tilt = 8f * sin(t * 6f)
                hop = abs(sin(t * 6f)) * 5f
                a1R = -150f + 30f * sin(t * 8f)
                a2R = -15f
                a1L = 150f - 30f * sin(t * 8f)
                a2L = 15f
            }
        }
        val mouth = if (speaking) {
            (abs(sin(t * 13f)) * (0.65f + 0.35f * sin(t * 5.3f))).coerceIn(0f, 1f)
        } else {
            0f
        }

        c.save()
        c.scale(width / 100f, height / 125f)
        c.translate(0f, bob - hop)
        c.rotate(tilt, 50f, 100f)

        // legs and boots
        roundRect(c, 41f, 95f, 49f, 108f, 3.5f, LEG)
        roundRect(c, 51f, 95f, 59f, 108f, 3.5f, LEG)
        roundRect(c, 39f, 106f, 49f, 112f, 3f, BOOT)
        roundRect(c, 51f, 106f, 61f, 112f, 3f, BOOT)

        // torso
        roundRect(c, 36f, 76f, 64f, 98f, 7f, BODY)
        fill.color = RED
        c.drawCircle(50f, 87f, 2.6f, fill)

        // arms
        arm(c, 64f, 86f, a1R, a2R)
        arm(c, 36f, 86f, a1L, a2L)

        // head: skin, helmet dome, outline
        fill.color = SKIN
        c.drawPath(headPath, fill)

        c.save()
        c.clipPath(headPath)
        fill.color = DOME
        c.drawRect(0f, 0f, 100f, 50f, fill)
        highlight.alpha = 150
        highlight.strokeWidth = 2.2f
        path.reset()
        path.moveTo(28f, 28f)
        path.quadTo(40f, 18f, 60f, 21f)
        c.drawPath(path, highlight)
        highlight.alpha = 90
        highlight.strokeWidth = 1.6f
        path.reset()
        path.moveTo(22f, 38f)
        path.quadTo(24f, 32f, 28f, 30f)
        c.drawPath(path, highlight)
        c.restore()

        line.strokeWidth = 2.6f
        c.drawPath(headPath, line)

        // ear pods
        fill.color = POD
        c.drawCircle(14f, 56f, 5.5f, fill)
        line.strokeWidth = 2.4f
        c.drawCircle(14f, 56f, 5.5f, line)
        c.drawCircle(14f, 56f, 2.4f, ring)
        fill.color = POD
        c.drawCircle(86f, 56f, 5.5f, fill)
        c.drawCircle(86f, 56f, 5.5f, line)
        c.drawCircle(86f, 56f, 2.4f, ring)

        // glowing red visor
        path.reset()
        path.moveTo(16f, 45f)
        path.quadTo(50f, 39f, 84f, 45f)
        path.lineTo(76f, 58f)
        path.quadTo(50f, 52f, 24f, 58f)
        path.close()
        glow.alpha = (90f + 30f * sin(t * 3f)).toInt().coerceIn(0, 255)
        c.drawPath(path, glow)
        fill.color = RED
        c.drawPath(path, fill)
        line.strokeWidth = 2.4f
        c.drawPath(path, line)
        highlight.color = Color.parseColor("#FFD0D0")
        highlight.alpha = 215
        highlight.strokeWidth = 1.6f
        val visorShine = Path()
        visorShine.moveTo(24f, 47f)
        visorShine.quadTo(50f, 43f, 76f, 47f)
        c.drawPath(visorShine, highlight)
        highlight.color = Color.WHITE

        // blush
        fill.color = Color.argb(150, 255, 122, 154)
        rect.set(23f, 62.8f, 35f, 69.2f)
        c.drawOval(rect, fill)
        rect.set(65f, 62.8f, 77f, 69.2f)
        c.drawOval(rect, fill)

        // mouth
        drawMouth(c, mouth)

        c.restore()

        postInvalidateDelayed(if (speaking || action != "idle") 16L else 33L)
    }

    // ---------- touch: tap, drag, pinch ----------

    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private var downX = 0f
    private var downY = 0f
    private var lastX = 0f
    private var lastY = 0f
    private var moved = false
    private var pinching = false

    private val scaleDetector = ScaleGestureDetector(
        context,
        object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScale(detector: ScaleGestureDetector): Boolean {
                onPinch?.invoke(detector.scaleFactor)
                return true
            }
        }
    )

    override fun onTouchEvent(e: MotionEvent): Boolean {
        scaleDetector.onTouchEvent(e)
        if (scaleDetector.isInProgress || e.pointerCount > 1) {
            pinching = true
            moved = true
            return true
        }
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = e.rawX
                downY = e.rawY
                lastX = downX
                lastY = downY
                moved = false
                pinching = false
            }
            MotionEvent.ACTION_MOVE -> {
                if (pinching) return true
                if (!moved && hypot(e.rawX - downX, e.rawY - downY) > touchSlop) {
                    moved = true
                    lastX = downX
                    lastY = downY
                }
                if (moved) {
                    onDrag?.invoke(e.rawX - lastX, e.rawY - lastY)
                    lastX = e.rawX
                    lastY = e.rawY
                }
            }
            MotionEvent.ACTION_UP -> {
                if (pinching || moved) {
                    onGestureEnd?.invoke()
                } else {
                    onTap?.invoke()
                }
                pinching = false
                moved = false
            }
            MotionEvent.ACTION_CANCEL -> {
                if (pinching || moved) onGestureEnd?.invoke()
                pinching = false
                moved = false
            }
        }
        return true
    }
}

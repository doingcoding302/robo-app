package com.robo.app

import android.animation.ValueAnimator
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.WindowManager
import androidx.core.app.NotificationCompat

/** Keeps the floating character on screen above every other app. */
class RoboService : Service() {

    companion object {
        const val ACTION_START = "com.robo.app.START"
        const val ACTION_STOP = "com.robo.app.STOP"
        const val ACTION_RESIZE = "com.robo.app.RESIZE"
        const val ACTION_RESET = "com.robo.app.RESET"
        private const val CHANNEL = "robo_overlay"
        private const val NOTIF_ID = 1

        @Volatile
        var running: Boolean = false
    }

    private lateinit var wm: WindowManager
    private var view: CharacterView? = null
    private var lp: WindowManager.LayoutParams? = null
    private var sizeDp: Float = Prefs.DEFAULT_DP.toFloat()

    private val metrics get() = resources.displayMetrics

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        createChannel()
        running = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundCompat()
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_RESIZE -> {
                sizeDp = Prefs.sizeDp(this).toFloat()
                applySize()
            }
            ACTION_RESET -> resetPosition()
        }
        if (view == null) show()
        return START_STICKY
    }

    override fun onDestroy() {
        val v = view
        if (v != null) {
            try {
                wm.removeView(v)
            } catch (e: Exception) {
                // already removed
            }
        }
        view = null
        lp = null
        running = false
        super.onDestroy()
    }

    // ---------- notification ----------

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(CHANNEL, "Robo overlay", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun startForegroundCompat() {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Robo is running")
            .setContentText("Tap to open settings")
            .setOngoing(true)
            .setContentIntent(open)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    // ---------- overlay window ----------

    private fun px(dp: Float): Int = (dp * metrics.density).toInt()

    private fun statusBarHeight(): Int {
        val id = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) resources.getDimensionPixelSize(id) else px(24f)
    }

    private fun defaultX(width: Int): Int = metrics.widthPixels - width - px(8f)

    private fun defaultY(): Int = statusBarHeight() + px(8f)

    @Suppress("DEPRECATION")
    private fun show() {
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }
        sizeDp = Prefs.sizeDp(this).toFloat()
        val h = px(sizeDp)
        val w = (h * 0.8f).toInt()
        val type = if (Build.VERSION.SDK_INT >= 26) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val p = WindowManager.LayoutParams(
            w,
            h,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        p.gravity = Gravity.TOP or Gravity.START
        val savedX = Prefs.posX(this)
        val savedY = Prefs.posY(this)
        p.x = if (savedX >= 0) savedX else defaultX(w)
        p.y = if (savedY >= 0) savedY else defaultY()
        clamp(p)

        val v = CharacterView(this)
        v.onTap = {
            RoboState.play("wave", 1800L)
            val chat = Intent(this, ChatActivity::class.java)
            chat.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(chat)
        }
        v.onDrag = { dx, dy ->
            p.x += Math.round(dx)
            p.y += Math.round(dy)
            clamp(p)
            if (v.isAttachedToWindow) wm.updateViewLayout(v, p)
        }
        v.onGestureEnd = { snapToEdge() }
        v.onPinch = { factor ->
            sizeDp = (sizeDp * factor).coerceIn(Prefs.MIN_DP.toFloat(), Prefs.MAX_DP.toFloat())
            Prefs.setSizeDp(this, sizeDp.toInt())
            applySize()
        }

        wm.addView(v, p)
        view = v
        lp = p
    }

    private fun clamp(p: WindowManager.LayoutParams) {
        val maxX = maxOf(0, metrics.widthPixels - p.width)
        val maxY = maxOf(0, metrics.heightPixels - p.height)
        p.x = p.x.coerceIn(0, maxX)
        p.y = p.y.coerceIn(0, maxY)
    }

    private fun applySize() {
        val p = lp ?: return
        val v = view ?: return
        val h = px(sizeDp)
        p.height = h
        p.width = (h * 0.8f).toInt()
        clamp(p)
        wm.updateViewLayout(v, p)
        Prefs.setPos(this, p.x, p.y)
    }

    private fun resetPosition() {
        Prefs.resetPos(this)
        val p = lp ?: return
        val v = view ?: return
        p.x = defaultX(p.width)
        p.y = defaultY()
        clamp(p)
        wm.updateViewLayout(v, p)
    }

    private fun snapToEdge() {
        val p = lp ?: return
        val v = view ?: return
        val margin = px(6f)
        val target = if (p.x + p.width / 2 < metrics.widthPixels / 2) {
            margin
        } else {
            metrics.widthPixels - p.width - margin
        }
        Prefs.setPos(this, target, p.y)
        val animator = ValueAnimator.ofInt(p.x, target)
        animator.duration = 160L
        animator.addUpdateListener { a ->
            p.x = a.animatedValue as Int
            if (v.isAttachedToWindow) wm.updateViewLayout(v, p)
        }
        animator.start()
    }
}

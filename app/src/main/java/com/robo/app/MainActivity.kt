package com.robo.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class MainActivity : AppCompatActivity() {

    private lateinit var status: TextView
    private lateinit var toggle: Button
    private lateinit var sizeLabel: TextView
    private lateinit var seek: SeekBar

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private fun label(s: String, size: Float, color: Int = Color.WHITE, bold: Boolean = false): TextView {
        val t = TextView(this)
        t.text = s
        t.textSize = size
        t.setTextColor(color)
        if (bold) t.setTypeface(t.typeface, Typeface.BOLD)
        return t
    }

    private fun btn(s: String, onClick: () -> Unit): Button {
        val b = Button(this)
        b.text = s
        b.isAllCaps = false
        b.setOnClickListener { onClick() }
        return b
    }

    private fun LinearLayout.put(v: View, top: Int = 12) {
        val params = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        params.topMargin = dp(top)
        addView(v, params)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        RoboVoice.init(this)

        val root = LinearLayout(this)
        root.orientation = LinearLayout.VERTICAL
        root.setPadding(dp(20), dp(28), dp(20), dp(28))

        root.put(label("Robo", 30f, Color.WHITE, true), 0)
        root.put(label("Stage 1: floating character, chat and voice", 14f, Color.parseColor("#9CA3AF")), 4)

        status = label("", 15f)
        root.put(status, 24)

        root.put(btn("Allow 'Display over other apps'") {
            startActivity(
                Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
            )
        })

        toggle = btn("Start Robo") {
            if (RoboService.running) {
                stopService(Intent(this, RoboService::class.java))
            } else if (!Settings.canDrawOverlays(this)) {
                Toast.makeText(this, "Allow 'Display over other apps' first", Toast.LENGTH_LONG).show()
            } else {
                val i = Intent(this, RoboService::class.java)
                i.action = RoboService.ACTION_START
                ContextCompat.startForegroundService(this, i)
            }
            window.decorView.postDelayed({ refresh() }, 600L)
        }
        root.put(toggle)

        sizeLabel = label("", 15f)
        root.put(sizeLabel, 24)
        seek = SeekBar(this)
        seek.max = Prefs.MAX_DP - Prefs.MIN_DP
        seek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(bar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (!fromUser) return
                val value = progress + Prefs.MIN_DP
                Prefs.setSizeDp(this@MainActivity, value)
                sizeLabel.text = "Size: $value dp"
                if (RoboService.running) {
                    val i = Intent(this@MainActivity, RoboService::class.java)
                    i.action = RoboService.ACTION_RESIZE
                    startService(i)
                }
            }

            override fun onStartTrackingTouch(bar: SeekBar?) {}
            override fun onStopTrackingTouch(bar: SeekBar?) {}
        })
        root.put(seek, 4)
        root.put(label("You can also pinch the robot to resize it, and drag it anywhere.", 12f, Color.parseColor("#9CA3AF")), 4)

        root.put(btn("Reset position to top-right") {
            Prefs.resetPos(this)
            if (RoboService.running) {
                val i = Intent(this, RoboService::class.java)
                i.action = RoboService.ACTION_RESET
                startService(i)
            }
        }, 16)

        root.put(label("Try the animations", 15f, Color.WHITE, true), 24)
        val row = LinearLayout(this)
        row.orientation = LinearLayout.HORIZONTAL
        for ((name, act) in listOf("Wave" to "wave", "Salute" to "salute", "Dance" to "dance")) {
            row.addView(
                btn(name) { RoboState.play(act, 3500L) },
                LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            )
        }
        row.addView(
            btn("Talk") { RoboVoice.speak(this, "Hello! I am Robo, your study buddy.") },
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        )
        root.put(row, 4)

        root.put(btn("Open chat") {
            startActivity(Intent(this, ChatActivity::class.java))
        }, 20)

        val scroll = ScrollView(this)
        scroll.setBackgroundColor(Color.BLACK)
        scroll.addView(root)
        setContentView(scroll)

        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 10)
        }
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    private fun refresh() {
        val ok = Settings.canDrawOverlays(this)
        status.text = if (ok) "Display over other apps: allowed" else "Display over other apps: not allowed yet"
        status.setTextColor(Color.parseColor(if (ok) "#2DD4BF" else "#FF6B6B"))
        toggle.text = if (RoboService.running) "Stop Robo" else "Start Robo"
        val value = Prefs.sizeDp(this)
        seek.progress = value - Prefs.MIN_DP
        sizeLabel.text = "Size: $value dp"
    }
}

#!/usr/bin/env bash
# Robo stage 1 setup: creates every project file, then commits and pushes to GitHub.
set -e
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
echo "Creating Robo project files in: $(pwd)"
mkdir -p ".github/workflows"
cat > ".github/workflows/build.yml" <<'__ROBO_EOF__'
name: Build Robo APK

on:
  push:
    branches: [main, master]
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - uses: android-actions/setup-android@v3

      - uses: gradle/actions/setup-gradle@v3
        with:
          gradle-version: '8.7'

      - name: Create signing key if missing
        run: |
          if [ ! -f app/robo.keystore ]; then
            keytool -genkeypair -keystore app/robo.keystore -storepass robo123 -keypass robo123 \
              -alias robo -keyalg RSA -keysize 2048 -validity 36500 -dname "CN=Robo, O=Robo, C=IN"
          fi

      - name: Build debug APK
        run: gradle assembleDebug --no-daemon --stacktrace

      - name: Name the APK
        run: cp app/build/outputs/apk/debug/app-debug.apk Robo.apk

      - name: Publish APK as a release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: build-${{ github.run_number }}
          name: Robo build ${{ github.run_number }}
          files: Robo.apk
__ROBO_EOF__
cat > ".gitignore" <<'__ROBO_EOF__'
.gradle/
build/
local.properties
.idea/
*.iml
.DS_Store
.kotlin/
__ROBO_EOF__
mkdir -p "app"
cat > "app/build.gradle.kts" <<'__ROBO_EOF__'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.robo.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.robo.app"
        minSdk = 23
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
    }

    // A fixed signing key lives in the repo so every new build can be installed
    // over the previous one without uninstalling. Personal use only.
    signingConfigs {
        create("robo") {
            storeFile = file("robo.keystore")
            storePassword = "robo123"
            keyAlias = "robo"
            keyPassword = "robo123"
        }
    }

    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("robo")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
}
__ROBO_EOF__
mkdir -p "app/src/main"
cat > "app/src/main/AndroidManifest.xml" <<'__ROBO_EOF__'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <queries>
        <intent>
            <action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.LAUNCHER" />
        </intent>
        <intent>
            <action android:name="android.intent.action.TTS_SERVICE" />
        </intent>
        <intent>
            <action android:name="android.speech.action.RECOGNIZE_SPEECH" />
        </intent>
    </queries>

    <application
        android:allowBackup="true"
        android:label="Robo"
        android:supportsRtl="true"
        android:theme="@style/Theme.Robo">

        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <activity
            android:name=".ChatActivity"
            android:exported="false"
            android:launchMode="singleTop"
            android:windowSoftInputMode="adjustResize" />

        <service
            android:name=".RoboService"
            android:exported="false"
            android:foregroundServiceType="specialUse">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="floating_assistant_overlay" />
        </service>
    </application>
</manifest>
__ROBO_EOF__
mkdir -p "app/src/main/java/com/robo/app"
cat > "app/src/main/java/com/robo/app/CharacterView.kt" <<'__ROBO_EOF__'
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
__ROBO_EOF__
mkdir -p "app/src/main/java/com/robo/app"
cat > "app/src/main/java/com/robo/app/ChatActivity.kt" <<'__ROBO_EOF__'
package com.robo.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.speech.RecognizerIntent
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.EditText
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity

class ChatActivity : AppCompatActivity() {

    private lateinit var log: TextView
    private lateinit var scroll: ScrollView
    private lateinit var input: EditText

    private val speechLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == RESULT_OK) {
            val said = result.data
                ?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                ?.firstOrNull()
            if (!said.isNullOrBlank()) handle(said)
        }
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private fun btn(s: String, onClick: () -> Unit): Button {
        val b = Button(this)
        b.text = s
        b.isAllCaps = false
        b.setOnClickListener { onClick() }
        return b
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        RoboVoice.init(this)

        val root = LinearLayout(this)
        root.orientation = LinearLayout.VERTICAL
        root.setBackgroundColor(Color.BLACK)
        root.setPadding(dp(16), dp(20), dp(16), dp(12))

        val title = TextView(this)
        title.text = "Robo"
        title.textSize = 24f
        title.setTextColor(Color.WHITE)
        title.setTypeface(title.typeface, Typeface.BOLD)
        root.addView(title)

        log = TextView(this)
        log.textSize = 16f
        log.setTextColor(Color.parseColor("#E5E7EB"))
        log.setPadding(0, dp(8), 0, dp(8))
        scroll = ScrollView(this)
        scroll.addView(log)
        root.addView(scroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        // quick commands
        val chips = LinearLayout(this)
        chips.orientation = LinearLayout.HORIZONTAL
        for (cmd in listOf("hello", "salute", "dance", "what time is it", "open youtube", "search physics notes")) {
            chips.addView(btn(cmd) { handle(cmd) })
        }
        val chipScroll = HorizontalScrollView(this)
        chipScroll.addView(chips)
        root.addView(chipScroll)

        // input row
        val row = LinearLayout(this)
        row.orientation = LinearLayout.HORIZONTAL
        input = EditText(this)
        input.hint = "Type a command"
        input.setTextColor(Color.WHITE)
        input.setHintTextColor(Color.parseColor("#6B7280"))
        input.imeOptions = EditorInfo.IME_ACTION_SEND
        input.isSingleLine = true
        input.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND) {
                send()
                true
            } else {
                false
            }
        }
        row.addView(input, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(btn("Mic") { listen() })
        row.addView(btn("Send") { send() })
        root.addView(row)

        setContentView(root)

        append("Robo: Hi! Try: open YouTube, search physics notes, dance, salute, or tap Mic and talk.")
    }

    private fun send() {
        val text = input.text.toString().trim()
        if (text.isEmpty()) return
        input.setText("")
        handle(text)
    }

    private fun listen() {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        intent.putExtra(
            RecognizerIntent.EXTRA_LANGUAGE_MODEL,
            RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
        )
        intent.putExtra(RecognizerIntent.EXTRA_PROMPT, "Say a command")
        try {
            speechLauncher.launch(intent)
        } catch (e: ActivityNotFoundException) {
            Toast.makeText(this, "Voice input is not available on this device", Toast.LENGTH_LONG).show()
        }
    }

    private fun handle(text: String) {
        append("You: $text")
        val reply = Commands.handle(this, text)
        append("Robo: $reply")
        RoboVoice.speak(this, reply)
    }

    private fun append(line: String) {
        log.append(line + "\n\n")
        scroll.post { scroll.fullScroll(ScrollView.FOCUS_DOWN) }
    }
}
__ROBO_EOF__
mkdir -p "app/src/main/java/com/robo/app"
cat > "app/src/main/java/com/robo/app/Commands.kt" <<'__ROBO_EOF__'
package com.robo.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Understands the simple commands for Stage 1. Gemini answers arrive in Stage 2. */
object Commands {
    private val aliases = mapOf(
        "yt" to "youtube",
        "insta" to "instagram",
        "fb" to "facebook",
        "whats app" to "whatsapp",
        "gmail" to "gmail",
        "maps" to "maps"
    )

    fun handle(ctx: Context, raw: String): String {
        val text = raw.trim()
        val s = text.lowercase(Locale.getDefault())
        return when {
            s.isEmpty() -> "I didn't catch that."
            s.startsWith("open ") -> openApp(ctx, s.removePrefix("open ").trim())
            s.startsWith("launch ") -> openApp(ctx, s.removePrefix("launch ").trim())
            s.startsWith("search ") -> search(ctx, text.substring(7).trim())
            s.contains("movie time") -> {
                "Movie time is coming in a later update. Popcorn is on the way!"
            }
            s.contains("good night") -> {
                "Good night! Sleep animation is coming in a later update."
            }
            s.contains("salute") -> {
                RoboState.play("salute", 4000L)
                "Yes, sir!"
            }
            s.contains("dance") -> {
                RoboState.play("dance", 5000L)
                "Watch these moves!"
            }
            s.contains("wave") || s == "hi" || s == "hey" || s.startsWith("hello") -> {
                RoboState.play("wave", 3000L)
                "Hello! Nice to see you."
            }
            s.contains("who are you") -> "I'm Robo, your study buddy."
            s.contains("time") -> {
                "It's " + SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date()) + "."
            }
            else -> "I heard: $text. I will be able to answer questions like this once Gemini is connected in the next stage."
        }
    }

    private fun openApp(ctx: Context, requested: String): String {
        if (requested.isEmpty()) return "Which app should I open?"
        val name = aliases[requested] ?: requested
        val pm = ctx.packageManager
        val query = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val apps = pm.queryIntentActivities(query, 0)
        val match = apps.firstOrNull { it.loadLabel(pm).toString().lowercase(Locale.getDefault()) == name }
            ?: apps.firstOrNull { it.loadLabel(pm).toString().lowercase(Locale.getDefault()).contains(name) }
            ?: return "I couldn't find an app called $requested."
        val label = match.loadLabel(pm).toString()
        val launch = pm.getLaunchIntentForPackage(match.activityInfo.packageName)
            ?: return "I couldn't open $label."
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            ctx.startActivity(launch)
            "Opening $label."
        } catch (e: Exception) {
            "I couldn't open $label."
        }
    }

    private fun search(ctx: Context, query: String): String {
        if (query.isEmpty()) return "What should I search for?"
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com/search?q=" + Uri.encode(query)))
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            ctx.startActivity(intent)
            "Searching for $query."
        } catch (e: Exception) {
            "I couldn't start the search."
        }
    }
}
__ROBO_EOF__
mkdir -p "app/src/main/java/com/robo/app"
cat > "app/src/main/java/com/robo/app/MainActivity.kt" <<'__ROBO_EOF__'
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
__ROBO_EOF__
mkdir -p "app/src/main/java/com/robo/app"
cat > "app/src/main/java/com/robo/app/Prefs.kt" <<'__ROBO_EOF__'
package com.robo.app

import android.content.Context

object Prefs {
    const val MIN_DP = 60
    const val MAX_DP = 240
    const val DEFAULT_DP = 140

    private fun sp(c: Context) = c.getSharedPreferences("robo", Context.MODE_PRIVATE)

    fun sizeDp(c: Context): Int = sp(c).getInt("size", DEFAULT_DP).coerceIn(MIN_DP, MAX_DP)

    fun setSizeDp(c: Context, v: Int) {
        sp(c).edit().putInt("size", v.coerceIn(MIN_DP, MAX_DP)).apply()
    }

    // -1 means "use the default top-right position"
    fun posX(c: Context): Int = sp(c).getInt("x", -1)
    fun posY(c: Context): Int = sp(c).getInt("y", -1)

    fun setPos(c: Context, x: Int, y: Int) {
        sp(c).edit().putInt("x", x).putInt("y", y).apply()
    }

    fun resetPos(c: Context) {
        sp(c).edit().remove("x").remove("y").apply()
    }
}
__ROBO_EOF__
mkdir -p "app/src/main/java/com/robo/app"
cat > "app/src/main/java/com/robo/app/RoboService.kt" <<'__ROBO_EOF__'
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
__ROBO_EOF__
mkdir -p "app/src/main/java/com/robo/app"
cat > "app/src/main/java/com/robo/app/RoboState.kt" <<'__ROBO_EOF__'
package com.robo.app

import android.os.SystemClock

/** Shared state read by the floating character every frame. */
object RoboState {
    @Volatile
    var speaking: Boolean = false

    @Volatile
    private var action: String = "idle"

    @Volatile
    private var actionUntil: Long = 0L

    fun play(name: String, durationMs: Long = 3500L) {
        action = name
        actionUntil = SystemClock.uptimeMillis() + durationMs
    }

    fun currentAction(): String {
        if (action != "idle" && SystemClock.uptimeMillis() > actionUntil) {
            action = "idle"
        }
        return action
    }
}
__ROBO_EOF__
mkdir -p "app/src/main/java/com/robo/app"
cat > "app/src/main/java/com/robo/app/RoboVoice.kt" <<'__ROBO_EOF__'
package com.robo.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale

/** Text-to-speech wrapper. While Robo speaks, RoboState.speaking is true so the mouth moves. */
object RoboVoice {
    private var tts: TextToSpeech? = null
    private var ready = false
    private var pending: String? = null
    private val handler = Handler(Looper.getMainLooper())
    private val stopTalking = Runnable { RoboState.speaking = false }

    fun init(context: Context) {
        if (tts != null) return
        val app = context.applicationContext
        tts = TextToSpeech(app) { status ->
            val engine = tts
            if (status == TextToSpeech.SUCCESS && engine != null) {
                val result = engine.setLanguage(Locale.getDefault())
                if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                    engine.setLanguage(Locale.US)
                }
                engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {
                        RoboState.speaking = true
                    }

                    override fun onDone(utteranceId: String?) {
                        RoboState.speaking = false
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) {
                        RoboState.speaking = false
                    }
                })
                ready = true
                val waiting = pending
                pending = null
                if (waiting != null) speak(app, waiting)
            }
        }
    }

    fun speak(context: Context, text: String) {
        init(context)
        if (!ready) {
            pending = text
            return
        }
        val engine = tts ?: return
        engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "robo-" + System.nanoTime())
        RoboState.speaking = true
        // Safety net in case the engine never reports that it finished.
        handler.removeCallbacks(stopTalking)
        handler.postDelayed(stopTalking, text.length * 90L + 3000L)
    }
}
__ROBO_EOF__
mkdir -p "app/src/main/res/values"
cat > "app/src/main/res/values/themes.xml" <<'__ROBO_EOF__'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.Robo" parent="Theme.MaterialComponents.NoActionBar">
        <item name="colorPrimary">#2DD4BF</item>
        <item name="colorOnPrimary">#000000</item>
        <item name="android:statusBarColor">#000000</item>
        <item name="android:navigationBarColor">#000000</item>
        <item name="android:windowBackground">#000000</item>
    </style>
</resources>
__ROBO_EOF__
cat > "build.gradle.kts" <<'__ROBO_EOF__'
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}
__ROBO_EOF__
cat > "gradle.properties" <<'__ROBO_EOF__'
org.gradle.jvmargs=-Xmx2g -Dfile.encoding=UTF-8
android.useAndroidX=true
android.nonTransitiveRClass=true
kotlin.code.style=official
__ROBO_EOF__
cat > "settings.gradle.kts" <<'__ROBO_EOF__'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "Robo"
include(":app")
__ROBO_EOF__
echo "All files created."
if [ ! -f app/robo.keystore ]; then
  if command -v keytool >/dev/null 2>&1; then
    keytool -genkeypair -keystore app/robo.keystore -storepass robo123 -keypass robo123 -alias robo -keyalg RSA -keysize 2048 -validity 36500 -dname "CN=Robo, O=Robo, C=IN" >/dev/null 2>&1 && echo "Signing key created." || echo "Could not create signing key here; GitHub will create one during the build."
  else
    echo "keytool not found; GitHub will create the signing key during the build."
  fi
fi
if [ -n "$ROBO_SKIP_PUSH" ]; then echo "Skipping git push (test mode)."; exit 0; fi
git add -A
git commit -m "Robo stage 1: floating character, chat, voice" || echo "Nothing new to commit."
git push origin HEAD
echo ""
echo "Done! Now open your repo on github.com, go to the Actions tab and wait for the green tick (about 5 minutes)."
echo "Then open the Releases section on the right side of the repo page and download Robo.apk."

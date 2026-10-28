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

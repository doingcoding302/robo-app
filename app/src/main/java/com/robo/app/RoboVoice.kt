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

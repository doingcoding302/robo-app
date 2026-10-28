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

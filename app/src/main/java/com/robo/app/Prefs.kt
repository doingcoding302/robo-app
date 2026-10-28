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

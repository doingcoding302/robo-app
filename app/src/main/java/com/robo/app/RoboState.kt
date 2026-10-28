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

package com.glamea.glamea

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build

/**
 * Application entry point. Creates notification channels so FCM
 * notifications delivered while the app is backgrounded/killed render
 * correctly on Android 8+ (without a channel they are silently dropped).
 */
class GlameaApp : Application() {

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            // General channel for booking / message / re-engagement updates.
            val general = NotificationChannel(
                CHANNEL_ID,
                "General notifications",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Booking, message and re-engagement updates"
            }
            manager.createNotificationChannel(general)

            // Incoming-call channel: high importance, vibration.
            val call = NotificationChannel(
                CHANNEL_CALL_ID,
                "Incoming calls",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming voice and video call alerts"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 500, 500)
            }
            manager.createNotificationChannel(call)
        }
    }

    companion object {
        const val CHANNEL_ID = "general"
        const val CHANNEL_CALL_ID = "incoming_call"
    }
}

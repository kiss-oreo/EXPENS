package com.kissoreo.expens

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock

/**
 * Updates the balance widget's capture label about every six hours.
 *
 * The check is permission-only. It does not receive a message, does not open
 * a message store, and does not read a message body. Labels match
 * [CaptureHealth] in Dart: a warning only for "Paused by you" and
 * "Permission revoked".
 */
class CaptureHealthCheck : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        refresh(context)
        schedule(context)
    }

    companion object {
        const val INTERVAL_MS = 6L * 60L * 60L * 1000L
        private const val PREFS = "HomeWidgetPreferences"
        private const val ACTION = "com.kissoreo.expens.CAPTURE_HEALTH_CHECK"

        fun schedule(context: Context) {
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val trigger = SystemClock.elapsedRealtime() + INTERVAL_MS
            @Suppress("DEPRECATION")
            alarm.setInexactRepeating(
                AlarmManager.ELAPSED_REALTIME,
                trigger,
                INTERVAL_MS,
                pending(context),
            )
        }

        fun refresh(context: Context) {
            val granted = context.checkSelfPermission(
                android.Manifest.permission.RECEIVE_SMS,
            ) == PackageManager.PERMISSION_GRANTED
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val enabled = prefs.getString("capture_enabled", "0") == "1"
            val ever = prefs.getString("capture_ever_enabled", "0") == "1"
            val label = when {
                enabled && !granted -> "Permission revoked"
                !enabled && ever -> "Paused by you"
                else -> ""
            }
            prefs.edit().putString("capture_label", label).apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, BalanceWidgetProvider::class.java),
            )
            if (ids.isEmpty()) return
            BalanceWidgetProvider().onUpdate(context, manager, ids, prefs)
        }

        private fun pending(context: Context): PendingIntent {
            val intent = Intent(context, CaptureHealthCheck::class.java).setAction(ACTION)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                }
            return PendingIntent.getBroadcast(context, 0, intent, flags)
        }
    }
}

/** Reschedules the permission check after reboot. Still does not read a message. */
class CaptureHealthBoot : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        CaptureHealthCheck.refresh(context)
        CaptureHealthCheck.schedule(context)
    }
}

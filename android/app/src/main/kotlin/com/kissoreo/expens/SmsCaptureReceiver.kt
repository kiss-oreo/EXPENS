package com.kissoreo.expens

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telephony.SmsMessage

/**
 * Manifest receiver for SMS_RECEIVED. Only the PDU in this intent is read.
 * The inbox content provider is never queried. READ_SMS is never requested.
 */
class SmsCaptureReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != "android.provider.Telephony.SMS_RECEIVED") return
        if (!SmsCaptureQueue.isEnabled(context)) return
        val bundle = intent.extras ?: return
        val pdus = bundle.get("pdus") as? Array<*> ?: return
        val format = bundle.getString("format")
        for (pdu in pdus) {
            val bytes = pdu as? ByteArray ?: continue
            val message = decode(bytes, format) ?: continue
            val body = message.messageBody ?: continue
            SmsCaptureQueue.enqueue(
                context,
                message.originatingAddress ?: "",
                body,
                message.timestampMillis,
            )
        }
        SmsCaptureEvents.dispatch(context)
        notify(context)
    }

    private fun decode(bytes: ByteArray, format: String?): SmsMessage? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            SmsMessage.createFromPdu(bytes, format)
        } else {
            @Suppress("DEPRECATION")
            SmsMessage.createFromPdu(bytes)
        }
    } catch (_: Exception) {
        null
    }

    private fun notify(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    "capture",
                    "Detected transactions",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
        val open = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            context,
            0,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, "capture")
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle("Expens")
            .setContentText("Bank SMS received. Open Expens to record it.")
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        manager.notify(9100, notification)
    }
}

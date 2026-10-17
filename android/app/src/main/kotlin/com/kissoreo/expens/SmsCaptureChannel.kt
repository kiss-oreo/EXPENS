package com.kissoreo.expens

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

private const val SMS_CHANNEL = "expens/sms"

/**
 * Hands the just-arrived queue to Dart and stores the pause / debug toggles.
 * Does not touch Telephony or the SMS content provider.
 */
object SmsCaptureEvents {
    private var channel: MethodChannel? = null

    fun attach(context: Context, messenger: BinaryMessenger) {
        val method = MethodChannel(messenger, SMS_CHANNEL)
        channel = method
        method.setMethodCallHandler { call, result ->
            when (call.method) {
                "drain" -> {
                    val raw = SmsCaptureQueue.drain(context.applicationContext)
                    val array = JSONArray(raw)
                    val list = ArrayList<Map<String, Any?>>(array.length())
                    for (i in 0 until array.length()) {
                        val item = array.getJSONObject(i)
                        list.add(
                            mapOf(
                                "sender" to item.optString("sender"),
                                "body" to item.optString("body"),
                                "receivedAt" to item.optLong("receivedAt"),
                            ),
                        )
                    }
                    result.success(list)
                }
                "setEnabled" -> {
                    SmsCaptureQueue.setEnabled(
                        context.applicationContext,
                        call.arguments as? Boolean ?: false,
                    )
                    result.success(null)
                }
                "setKeepRaw" -> {
                    SmsCaptureQueue.setKeepRaw(
                        context.applicationContext,
                        call.arguments as? Boolean ?: false,
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispatch(context: Context) {
        val method = channel ?: return
        val raw = SmsCaptureQueue.drain(context.applicationContext)
        val array = JSONArray(raw)
        for (i in 0 until array.length()) {
            val item = array.getJSONObject(i)
            method.invokeMethod(
                "onSms",
                mapOf(
                    "sender" to item.optString("sender"),
                    "body" to item.optString("body"),
                    "receivedAt" to item.optLong("receivedAt"),
                ),
            )
        }
    }
}

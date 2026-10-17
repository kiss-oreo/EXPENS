package com.kissoreo.expens

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Transient queue of SMS that just arrived. The BroadcastReceiver writes
 * here; Dart drains it. This is not an inbox scan and not a stored archive:
 * each row is deleted once the parser has taken the fields it needs.
 */
object SmsCaptureQueue {
    private const val PREFS = "expens_capture"
    private const val ENABLED = "enabled"
    private const val KEEP_RAW = "keep_raw"
    private const val FILE = "sms_queue.json"

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(ENABLED, enabled)
            .apply()
    }

    fun setKeepRaw(context: Context, keep: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEEP_RAW, keep)
            .apply()
    }

    fun enqueue(context: Context, sender: String, body: String, receivedAt: Long) {
        if (!isEnabled(context)) return
        val array = read(context)
        val item = JSONObject()
            .put("sender", sender)
            .put("body", body)
            .put("receivedAt", receivedAt)
        array.put(item)
        write(context, array)
    }

    fun drain(context: Context): String {
        val array = read(context)
        write(context, JSONArray())
        return array.toString()
    }

    private fun file(context: Context) = File(context.filesDir, FILE)

    private fun read(context: Context): JSONArray {
        val f = file(context)
        if (!f.exists()) return JSONArray()
        return try {
            JSONArray(f.readText())
        } catch (_: Exception) {
            JSONArray()
        }
    }

    private fun write(context: Context, array: JSONArray) {
        file(context).writeText(array.toString())
    }
}

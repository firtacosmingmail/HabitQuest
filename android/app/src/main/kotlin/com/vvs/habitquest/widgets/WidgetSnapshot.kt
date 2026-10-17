package com.vvs.habitquest.widgets

import android.content.SharedPreferences
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Read-only view of the snapshot the Dart widget bridge writes
 * (`lib/features/widgets_bridge/`). The schema and every name are defined in
 * `docs/WIDGETS.md` and `widget_constants.dart`; the values below must match.
 *
 * Native code only reads [SNAPSHOT_KEY]. It never writes it or the toggle
 * queue: check-offs go through home_widget's background callback.
 */
object WidgetContract {
    /** SharedPreferences file home_widget writes to (`HomeWidgetPlugin.PREFERENCES`). */
    const val PREFERENCES_NAME = "HomeWidgetPreferences"
    const val SNAPSHOT_KEY = "hq_widget_snapshot"

    const val STATE_OK = "ok"
    const val STATE_SIGNED_OUT = "signedOut"
    const val STATE_NO_HABITS = "noHabits"

    const val OPEN_URI = "habitquest://open"
    const val QUOTES_URI = "habitquest://quotes"
    const val TOGGLE_URI_PREFIX = "habitquest://widget/toggle?habitId="

    /** home_widget's `HomeWidgetBackgroundIntent` action (runs the Dart interactive callback). */
    const val BACKGROUND_ACTION = "es.antonborri.home_widget.action.BACKGROUND"
}

data class WidgetHabit(
    val id: String,
    val name: String,
    val emoji: String,
    /** ARGB (0xAARRGGBB), already narrowed to a signed Int for Android colour APIs. */
    val color: Int,
    val done: Boolean,
    val toggleUri: String,
)

data class WidgetQuote(
    val text: String,
    val author: String?,
    val attribution: String,
)

/** The decoded snapshot, with the "older day means nothing is done yet" rule applied. */
data class WidgetSnapshot(
    val state: String,
    val date: String?,
    val habits: List<WidgetHabit>,
    val quote: WidgetQuote?,
) {
    val doneCount: Int get() = habits.count { it.done }
    val totalCount: Int get() = habits.size
    val isOk: Boolean get() = state == WidgetContract.STATE_OK && habits.isNotEmpty()

    companion object {
        val SIGNED_OUT = WidgetSnapshot(WidgetContract.STATE_SIGNED_OUT, null, emptyList(), null)

        /** Today's local calendar day as the bridge writes it (`yyyy-MM-dd`). */
        fun todayKey(now: Date = Date()): String =
            SimpleDateFormat("yyyy-MM-dd", Locale.US).format(now)

        fun read(prefs: SharedPreferences, today: String = todayKey()): WidgetSnapshot =
            parse(prefs.getString(WidgetContract.SNAPSHOT_KEY, null), today)

        /**
         * Parses [json]. A missing or broken snapshot, or an unknown state, is
         * [SIGNED_OUT]. If the snapshot's `date` is before [today] (the app has
         * not run since midnight), every habit is shown as not done.
         */
        fun parse(json: String?, today: String = todayKey()): WidgetSnapshot {
            if (json.isNullOrBlank()) return SIGNED_OUT
            return try {
                val root = JSONObject(json)
                val rawState = root.optString("state", WidgetContract.STATE_SIGNED_OUT)
                val state = when (rawState) {
                    WidgetContract.STATE_OK, WidgetContract.STATE_NO_HABITS -> rawState
                    else -> WidgetContract.STATE_SIGNED_OUT
                }
                val date = root.optStringOrNull("date")
                // ISO dates compare correctly as strings.
                val stale = date != null && date < today
                val habits = mutableListOf<WidgetHabit>()
                if (state == WidgetContract.STATE_OK) {
                    val array = root.optJSONArray("habits")
                    if (array != null) {
                        for (i in 0 until array.length()) {
                            val h = array.optJSONObject(i) ?: continue
                            val id = h.optStringOrNull("id") ?: continue
                            habits += WidgetHabit(
                                id = id,
                                name = h.optString("name", ""),
                                emoji = h.optStringOrNull("emoji") ?: "✅",
                                // Unsigned 32-bit in JSON: read as Long, keep the low 32 bits.
                                color = h.optLong("color", 0xFF7C4DFFL).toInt(),
                                done = !stale && h.optBoolean("done", false),
                                toggleUri = h.optStringOrNull("toggleUri")
                                    ?: (WidgetContract.TOGGLE_URI_PREFIX + android.net.Uri.encode(id)),
                            )
                        }
                    }
                }
                val quote = root.optJSONObject("quote")?.let { q ->
                    val text = q.optStringOrNull("text") ?: return@let null
                    val author = q.optStringOrNull("author")
                    WidgetQuote(
                        text = text,
                        author = author,
                        attribution = q.optStringOrNull("attribution")
                            ?: ("— " + (author ?: "Unknown")),
                    )
                }
                WidgetSnapshot(state, date, habits, quote)
            } catch (e: Exception) {
                SIGNED_OUT
            }
        }

        private fun JSONObject.optStringOrNull(key: String): String? =
            if (isNull(key)) null else optString(key).takeIf { it.isNotEmpty() }
    }
}

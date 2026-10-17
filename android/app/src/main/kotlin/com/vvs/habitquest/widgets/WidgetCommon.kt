package com.vvs.habitquest.widgets

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.ui.graphics.Color
import androidx.glance.action.Action
import androidx.glance.appwidget.action.actionSendBroadcast
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.color.ColorProvider
import androidx.glance.unit.ColorProvider
import com.vvs.habitquest.MainActivity
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
import es.antonborri.home_widget.HomeWidgetScheduler
import java.util.Calendar

/** Widget palette (the app's colours, `lib/core/theme/app_colors.dart`), light and dark. */
object WidgetColors {
    val background = ColorProvider(day = Color(0xFFFFFBFF), night = Color(0xFF1D1B22))
    val surface = ColorProvider(day = Color(0xFFF1ECFA), night = Color(0xFF2B2833))
    val onSurface = ColorProvider(day = Color(0xFF1C1B1F), night = Color(0xFFE6E1E9))
    val secondaryText = ColorProvider(day = Color(0xFF605D66), night = Color(0xFFB0ABB8))
    val primary = ColorProvider(day = Color(0xFF7C4DFF), night = Color(0xFFB39DFF))
    val outline = ColorProvider(day = Color(0xFF8E8A96), night = Color(0xFF8E8A96))
    val checkMark = ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFFFFFFFF))

    fun fixed(argb: Int): ColorProvider = ColorProvider(Color(argb))
}

/** Opens the app on [uri] (`habitquest://open` or `habitquest://quotes`) through Flutter deep linking. */
fun openAppAction(context: Context, uri: String): Action {
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri), context, MainActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    return actionStartActivity(intent)
}

/**
 * The check-off: the same broadcast as home_widget's
 * `HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse(toggleUri))`.
 * [HomeWidgetBackgroundReceiver] runs the Dart `widgetInteractivityCallback`
 * in a headless isolate (the app does not open); it updates the snapshot and
 * calls `updateWidget`, which redraws the row.
 */
fun toggleHabitAction(context: Context, toggleUri: String): Action {
    val intent = Intent(context, HomeWidgetBackgroundReceiver::class.java)
        .setAction(WidgetContract.BACKGROUND_ACTION)
        .setData(Uri.parse(toggleUri))
    return actionSendBroadcast(intent)
}

/**
 * Midnight roll-over. Arms home_widget's [HomeWidgetScheduler] for the next
 * few local midnights (a couple of seconds after, so `todayKey()` has already
 * changed). Each scheduled update ends in `onUpdate`, which calls this again,
 * so the chain never runs dry while a widget exists. Replaces earlier times,
 * so calling it often is cheap. Exact alarms are used when the app may
 * schedule them (`SCHEDULE_EXACT_ALARM`), inexact ones otherwise.
 */
object MidnightRefresh {
    private const val DAYS_AHEAD = 7
    private const val AFTER_MIDNIGHT_MS = 5_000L

    fun schedule(context: Context, receiverClassName: String) {
        try {
            HomeWidgetScheduler.schedule(context, receiverClassName, nextMidnights())
        } catch (e: Exception) {
            android.util.Log.w("HabitQuestWidgets", "Could not schedule the midnight refresh", e)
        }
    }

    fun cancel(context: Context, receiverClassName: String) {
        HomeWidgetScheduler.cancel(context, receiverClassName)
    }

    internal fun nextMidnights(now: Calendar = Calendar.getInstance()): List<Long> {
        val cal = (now.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        return (1..DAYS_AHEAD).map {
            cal.add(Calendar.DAY_OF_YEAR, 1)
            cal.timeInMillis + AFTER_MIDNIGHT_MS
        }
    }
}

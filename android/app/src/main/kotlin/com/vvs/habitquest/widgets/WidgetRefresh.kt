package com.vvs.habitquest.widgets

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import es.antonborri.home_widget.HomeWidgetBackgroundWorker
import kotlinx.coroutines.delay
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale
import java.util.UUID
import java.util.concurrent.TimeUnit

/**
 * Daily roll-over of the widgets while the app is not running (docs/WIDGETS.md,
 * "Daily roll-over without the app").
 *
 * The widgets only render the snapshot the Dart side writes, and only Dart can
 * fetch the quote of the day (`GET /quotes` needs the user's bearer token and
 * token refresh). So this schedules WorkManager work that wakes the Dart side
 * through home_widget's background callback with `habitquest://widget/refresh`;
 * Dart (`widget_background_refresh.dart`) reuses the app's auth + quotes code,
 * rewrites the snapshot and refreshes both widgets. No HTTP or auth in Kotlin.
 *
 * - a one-off a minute after every local midnight (no constraint, so the habits
 *   roll over offline too); offline, it enqueues a network-constrained catch-up;
 * - a periodic safety net every [PERIODIC_HOURS] hours (network-constrained),
 *   which also covers reboots, Doze and missed midnights. It makes no network
 *   call when the snapshot already has today's quote.
 *
 * Work exists only while at least one widget is on the home screen.
 */
object WidgetRefresh {
    private const val TAG = "HabitQuestWidgets"
    const val WORK_TAG = "hq-widget-refresh"
    private const val PERIODIC_NAME = "hq-widget-refresh-periodic"
    private const val MIDNIGHT_PREFIX = "hq-widget-refresh-midnight-"
    private const val CATCH_UP_NAME = "hq-widget-refresh-catchup"
    const val PERIODIC_HOURS = 4L
    private const val AFTER_MIDNIGHT_MS = 60_000L
    private const val BACKOFF_MINUTES = 15L

    /** Must match `WidgetConstants.refreshUri` in Dart. */
    const val REFRESH_URI = "habitquest://widget/refresh"

    /** Written by Dart when a refresh finished (`{"id": ..., "outcome": ...}`). */
    const val STATUS_KEY = "hq_widget_refresh_status"

    /** Arms the periodic and the next-midnight work (idempotent, cheap: KEEP). */
    fun schedule(context: Context) {
        try {
            val wm = WorkManager.getInstance(context)
            val periodic = PeriodicWorkRequestBuilder<WidgetRefreshWorker>(PERIODIC_HOURS, TimeUnit.HOURS)
                .setConstraints(networkConstraint())
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, BACKOFF_MINUTES, TimeUnit.MINUTES)
                .setInputData(workDataOf(WidgetRefreshWorker.KEY_KIND to WidgetRefreshWorker.KIND_PERIODIC))
                .addTag(WORK_TAG)
                .build()
            wm.enqueueUniquePeriodicWork(PERIODIC_NAME, ExistingPeriodicWorkPolicy.KEEP, periodic)
            scheduleMidnight(context, System.currentTimeMillis())
        } catch (e: Exception) {
            Log.w(TAG, "Could not schedule the widget refresh", e)
        }
    }

    /** Cancels everything once no widget is left. */
    fun cancelIfNoWidgets(context: Context) {
        if (hasWidgets(context)) return
        try {
            WorkManager.getInstance(context).cancelAllWorkByTag(WORK_TAG)
        } catch (e: Exception) {
            Log.w(TAG, "Could not cancel the widget refresh", e)
        }
    }

    /** The one-off a minute after the local midnight following [nowMs]; one unique name per night. */
    fun scheduleMidnight(context: Context, nowMs: Long) {
        val now = Calendar.getInstance().apply { timeInMillis = nowMs }
        val midnight = (now.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            add(Calendar.DAY_OF_YEAR, 1)
        }
        val day = String.format(
            Locale.US, "%04d-%02d-%02d",
            midnight.get(Calendar.YEAR), midnight.get(Calendar.MONTH) + 1, midnight.get(Calendar.DAY_OF_MONTH),
        )
        val delayMs = midnight.timeInMillis + AFTER_MIDNIGHT_MS - nowMs
        val request = OneTimeWorkRequestBuilder<WidgetRefreshWorker>()
            .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
            .setInputData(workDataOf(WidgetRefreshWorker.KEY_KIND to WidgetRefreshWorker.KIND_MIDNIGHT))
            .addTag(WORK_TAG)
            .build()
        WorkManager.getInstance(context)
            .enqueueUniqueWork(MIDNIGHT_PREFIX + day, ExistingWorkPolicy.KEEP, request)
    }

    /** Runs as soon as there is a network (after an offline midnight run). */
    fun enqueueCatchUp(context: Context) {
        val request = OneTimeWorkRequestBuilder<WidgetRefreshWorker>()
            .setConstraints(networkConstraint())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, BACKOFF_MINUTES, TimeUnit.MINUTES)
            .setInputData(workDataOf(WidgetRefreshWorker.KEY_KIND to WidgetRefreshWorker.KIND_CATCH_UP))
            .addTag(WORK_TAG)
            .build()
        WorkManager.getInstance(context)
            .enqueueUniqueWork(CATCH_UP_NAME, ExistingWorkPolicy.KEEP, request)
    }

    fun hasWidgets(context: Context): Boolean {
        val manager = AppWidgetManager.getInstance(context) ?: return false
        return listOf(TodayHabitsWidgetReceiver::class.java, DailyQuoteWidgetReceiver::class.java).any {
            manager.getAppWidgetIds(ComponentName(context, it)).isNotEmpty()
        }
    }

    private fun networkConstraint() =
        Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
}

/**
 * Wakes the Dart refresh (home_widget background callback) and waits briefly
 * for its outcome, so the process stays up during the fetch and WorkManager can
 * retry when it failed.
 */
class WidgetRefreshWorker(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val context = applicationContext
        val kind = inputData.getString(KEY_KIND) ?: KIND_PERIODIC
        // Keep the nightly chain going whatever happens below.
        if (kind == KIND_MIDNIGHT) {
            runCatching { WidgetRefresh.scheduleMidnight(context, System.currentTimeMillis() + 5 * 60_000L) }
        }
        if (!WidgetRefresh.hasWidgets(context)) return Result.success()

        val id = UUID.randomUUID().toString()
        val uri = Uri.parse(WidgetRefresh.REFRESH_URI).buildUpon().appendQueryParameter("id", id).build()
        HomeWidgetBackgroundWorker.enqueueWork(context, Intent().setData(uri))
        val outcome = awaitOutcome(context, id)
        Log.i("HabitQuestWidgets", "Widget refresh ($kind): ${outcome ?: "no answer"}")
        return when {
            outcome != OUTCOME_RETRY -> Result.success()
            kind == KIND_MIDNIGHT -> {
                runCatching { WidgetRefresh.enqueueCatchUp(context) }
                Result.success()
            }
            else -> Result.retry()
        }
    }

    private suspend fun awaitOutcome(context: Context, id: String): String? {
        val prefs = context.getSharedPreferences(WidgetContract.PREFERENCES_NAME, Context.MODE_PRIVATE)
        val deadline = System.currentTimeMillis() + TIMEOUT_MS
        while (System.currentTimeMillis() < deadline) {
            val raw = prefs.getString(WidgetRefresh.STATUS_KEY, null)
            if (raw != null) {
                try {
                    val status = JSONObject(raw)
                    if (status.optString("id") == id) return status.optString("outcome")
                } catch (_: Exception) {
                    // Unreadable: keep waiting.
                }
            }
            delay(POLL_MS)
        }
        return null
    }

    companion object {
        const val KEY_KIND = "kind"
        const val KIND_PERIODIC = "periodic"
        const val KIND_MIDNIGHT = "midnight"
        const val KIND_CATCH_UP = "catchUp"
        private const val OUTCOME_RETRY = "retryLater"
        private const val TIMEOUT_MS = 30_000L
        private const val POLL_MS = 500L
    }
}

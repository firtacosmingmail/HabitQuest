package com.vvs.habitquest.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextDecoration
import androidx.glance.text.TextStyle
import com.vvs.habitquest.R
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import es.antonborri.home_widget.HomeWidgetPreviews

/** "Today's habits": header (opens the app) + a scrollable list of today's due habits. */
class TodayHabitsWidget : GlanceAppWidget() {

    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override val sizeMode = SizeMode.Responsive(setOf(SMALL, MEDIUM, LARGE))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            val prefs = currentState<HomeWidgetGlanceState>().preferences
            TodayHabitsContent(WidgetSnapshot.read(prefs))
        }
    }

    /** Generated gallery preview on Android 15+ (sample data, never the user's habits). */
    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        provideContent { TodayHabitsContent(SAMPLE) }
    }

    companion object {
        val SMALL = DpSize(110.dp, 110.dp)
        val MEDIUM = DpSize(250.dp, 110.dp)
        val LARGE = DpSize(250.dp, 250.dp)

        val SAMPLE = WidgetSnapshot(
            state = WidgetContract.STATE_OK,
            date = null,
            habits = listOf(
                WidgetHabit("1", "Drink water", "💧", 0xFF4CC9F0.toInt(), true, ""),
                WidgetHabit("2", "Walk 20 minutes", "🚶", 0xFF2EC4B6.toInt(), false, ""),
                WidgetHabit("3", "Read 10 pages", "📚", 0xFFFF8C42.toInt(), false, ""),
            ),
            quote = null,
        )
    }
}

@Composable
private fun TodayHabitsContent(snapshot: WidgetSnapshot) {
    val context = LocalContext.current
    val compact = LocalSize.current.width < TodayHabitsWidget.MEDIUM.width
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .appWidgetBackground()
            .cornerRadius(20.dp)
            .background(WidgetColors.background)
            .padding(horizontal = 12.dp, vertical = 10.dp),
    ) {
        Header(snapshot, compact)
        Spacer(GlanceModifier.height(6.dp))
        if (snapshot.isOk) {
            LazyColumn(modifier = GlanceModifier.fillMaxSize()) {
                items(snapshot.habits, itemId = { it.id.hashCode().toLong() }) { habit ->
                    HabitRow(habit, compact)
                }
            }
        } else {
            OpenAppPrompt(
                message = context.getString(
                    if (snapshot.state == WidgetContract.STATE_NO_HABITS) {
                        R.string.widget_habits_none_today
                    } else {
                        R.string.widget_habits_signed_out
                    },
                ),
            )
        }
    }
}

@Composable
private fun Header(snapshot: WidgetSnapshot, compact: Boolean) {
    val context = LocalContext.current
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .clickable(openAppAction(context, WidgetContract.OPEN_URI)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = context.getString(
                if (compact) R.string.widget_habits_title_short else R.string.widget_habits_title,
            ),
            style = TextStyle(
                color = WidgetColors.primary,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
            ),
            maxLines = 1,
            modifier = GlanceModifier.defaultWeight(),
        )
        if (snapshot.isOk) {
            Text(
                text = "${snapshot.doneCount}/${snapshot.totalCount}",
                style = TextStyle(
                    color = WidgetColors.secondaryText,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun HabitRow(habit: WidgetHabit, compact: Boolean) {
    val context = LocalContext.current
    val label = context.getString(
        if (habit.done) R.string.widget_habit_uncheck else R.string.widget_habit_check,
        habit.name,
    )
    // The whole row is the touch target of the checkbox (a bigger target
    // than the box alone). Both fire the same background check-off.
    val toggle = if (habit.toggleUri.isNotEmpty()) toggleHabitAction(context, habit.toggleUri) else null
    Column(modifier = GlanceModifier.fillMaxWidth().padding(vertical = 3.dp)) {
        Row(
            modifier = GlanceModifier
                .fillMaxWidth()
                .cornerRadius(14.dp)
                .background(WidgetColors.surface)
                .padding(horizontal = 10.dp, vertical = 7.dp)
                .let { if (toggle != null) it.clickable(toggle) else it }
                .semantics { contentDescription = label },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (!compact) {
                Text(text = habit.emoji, style = TextStyle(fontSize = 18.sp), maxLines = 1)
                Spacer(GlanceModifier.width(8.dp))
            }
            Text(
                text = if (compact) "${habit.emoji} ${habit.name}" else habit.name,
                style = TextStyle(
                    color = if (habit.done) WidgetColors.secondaryText else WidgetColors.onSurface,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    textDecoration = if (habit.done) TextDecoration.LineThrough else TextDecoration.None,
                ),
                maxLines = 1,
                modifier = GlanceModifier.defaultWeight(),
            )
            Spacer(GlanceModifier.width(6.dp))
            CheckBoxImage(habit)
        }
    }
}

@Composable
private fun CheckBoxImage(habit: WidgetHabit) {
    Box(modifier = GlanceModifier.size(24.dp), contentAlignment = Alignment.Center) {
        if (habit.done) {
            Image(
                provider = ImageProvider(R.drawable.widget_checkbox_fill),
                contentDescription = null,
                colorFilter = ColorFilter.tint(WidgetColors.fixed(habit.color)),
                modifier = GlanceModifier.size(24.dp),
            )
            Image(
                provider = ImageProvider(R.drawable.widget_check_mark),
                contentDescription = null,
                colorFilter = ColorFilter.tint(WidgetColors.checkMark),
                modifier = GlanceModifier.size(18.dp),
            )
        } else {
            Image(
                provider = ImageProvider(R.drawable.widget_checkbox_outline),
                contentDescription = null,
                colorFilter = ColorFilter.tint(WidgetColors.fixed(habit.color)),
                modifier = GlanceModifier.size(24.dp),
            )
        }
    }
}

/** The "Open HabitQuest" state (signed out, no snapshot yet, or nothing due today). */
@Composable
internal fun OpenAppPrompt(message: String, uri: String = WidgetContract.OPEN_URI) {
    val context = LocalContext.current
    Column(
        modifier = GlanceModifier.fillMaxSize().clickable(openAppAction(context, uri)),
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = message,
            style = TextStyle(color = WidgetColors.secondaryText, fontSize = 13.sp),
            maxLines = 3,
        )
        Spacer(GlanceModifier.height(6.dp))
        Text(
            text = context.getString(R.string.widget_open_app),
            style = TextStyle(
                color = WidgetColors.primary,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
            ),
            maxLines = 1,
        )
    }
}

class TodayHabitsWidgetReceiver : HomeWidgetGlanceWidgetReceiver<TodayHabitsWidget>() {
    override val glanceAppWidget = TodayHabitsWidget()

    /** Static sample preview: register it once per version (see [HomeWidgetPreviews]). */
    override fun previewFingerprint(context: Context): String = "today-habits-v1"

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        MidnightRefresh.schedule(context, javaClass.name)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        MidnightRefresh.cancel(context, javaClass.name)
    }
}

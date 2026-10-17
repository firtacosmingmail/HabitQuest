package com.vvs.habitquest.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontStyle
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import com.vvs.habitquest.R
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver

/** "Daily quote": today's quote and author; a tap opens the Quotes screen. */
class DailyQuoteWidget : GlanceAppWidget() {

    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override val sizeMode = SizeMode.Responsive(setOf(SMALL, WIDE, LARGE))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            val prefs = currentState<HomeWidgetGlanceState>().preferences
            DailyQuoteContent(WidgetSnapshot.read(prefs).quote)
        }
    }

    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        provideContent { DailyQuoteContent(SAMPLE) }
    }

    companion object {
        val SMALL = DpSize(110.dp, 110.dp)
        val WIDE = DpSize(250.dp, 110.dp)
        val LARGE = DpSize(250.dp, 200.dp)

        val SAMPLE = WidgetQuote(
            text = "We are what we repeatedly do.",
            author = "Will Durant",
            attribution = "— Will Durant",
        )
    }
}

@Composable
private fun DailyQuoteContent(quote: WidgetQuote?) {
    val context = LocalContext.current
    val size = LocalSize.current
    val small = size.width < DailyQuoteWidget.WIDE.width
    val large = size.height >= DailyQuoteWidget.LARGE.height
    val quoteSize = when {
        large -> 20.sp
        small -> 14.sp
        else -> 16.sp
    }
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .appWidgetBackground()
            .cornerRadius(20.dp)
            .background(WidgetColors.background)
            .padding(horizontal = 14.dp, vertical = 12.dp)
            .clickable(openAppAction(context, WidgetContract.QUOTES_URI)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = context.getString(R.string.widget_quote_title),
            style = TextStyle(
                color = WidgetColors.primary,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
            ),
            maxLines = 1,
        )
        Spacer(GlanceModifier.height(6.dp))
        if (quote == null) {
            Text(
                text = context.getString(R.string.widget_quote_empty),
                style = TextStyle(color = WidgetColors.secondaryText, fontSize = 13.sp),
                maxLines = 3,
            )
            Spacer(GlanceModifier.height(4.dp))
            Text(
                text = context.getString(R.string.widget_open_app),
                style = TextStyle(
                    color = WidgetColors.primary,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                ),
                maxLines = 1,
            )
        } else {
            Text(
                text = "“${quote.text}”",
                style = TextStyle(
                    color = WidgetColors.onSurface,
                    fontSize = quoteSize,
                    fontWeight = FontWeight.Medium,
                    fontStyle = FontStyle.Italic,
                ),
                maxLines = if (large) 8 else if (small) 5 else 4,
                modifier = GlanceModifier.fillMaxWidth(),
            )
            Spacer(GlanceModifier.height(6.dp))
            Text(
                text = quote.attribution,
                style = TextStyle(
                    color = WidgetColors.secondaryText,
                    fontSize = 12.sp,
                    textAlign = TextAlign.End,
                ),
                maxLines = 1,
                modifier = GlanceModifier.fillMaxWidth(),
            )
        }
    }
}

class DailyQuoteWidgetReceiver : HomeWidgetGlanceWidgetReceiver<DailyQuoteWidget>() {
    override val glanceAppWidget = DailyQuoteWidget()

    override fun previewFingerprint(context: Context): String = "daily-quote-v1"

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        MidnightRefresh.schedule(context, javaClass.name)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        MidnightRefresh.cancel(context, javaClass.name)
    }
}

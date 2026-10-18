package com.vvs.habitquest

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

/**
 * Home-screen widget links (`habitquest://open`, `habitquest://quotes`,
 * `habitquest://widget/...`, see docs/WIDGETS.md) must be handled exactly
 * once.
 *
 * A widget tap that starts the app cold becomes the task's root intent, and
 * Android hands that intent again to a re-created activity: after the
 * process was killed in the background (`savedInstanceState != null`) or when
 * the task is relaunched from Recents (`FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY`).
 * Flutter reads the initial route from the intent in `onStart`, so such a
 * replay would open the Quotes screen (or repeat a check-off) again. In those
 * cases the link is replaced by a plain launcher intent before Flutter sees
 * it. Fresh taps (cold start, or `onNewIntent` while running) pass through.
 */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        val launched = intent
        if (launched != null && isWidgetLink(launched) &&
            (savedInstanceState != null ||
                launched.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0)
        ) {
            intent = launcherIntent()
        }
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // The link has been handed to Flutter; keep it out of getIntent().
        if (isWidgetLink(intent)) setIntent(launcherIntent())
    }

    private fun launcherIntent(): Intent =
        Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .setClass(this, MainActivity::class.java)

    private fun isWidgetLink(intent: Intent): Boolean {
        val data = intent.data ?: return false
        return intent.action == Intent.ACTION_VIEW &&
            data.scheme == "habitquest" &&
            data.host in WIDGET_HOSTS
    }

    private companion object {
        val WIDGET_HOSTS = setOf("open", "quotes", "widget")
    }
}

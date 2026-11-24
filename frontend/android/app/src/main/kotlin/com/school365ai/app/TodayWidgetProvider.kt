package com.school365ai.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

// The "Today" home-screen widget of the Staff and Family apps
// (docs/mobile-apps-review.md, M10, 6.1). Declared only in their manifests
// (src/teacher, src/family), so the Bus app has none.
//
// It draws what the app last saved (lib/core/home_widget/today_card.dart)
// and fetches nothing itself: the app saves a new card when it opens and a
// background job about every half hour. A tap opens the app.
class TodayWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.today_widget)
            views.setOnClickPendingIntent(
                R.id.today_widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )

            // Before the app has saved anything: a way in, never a blank box.
            val title = widgetData.getString("today_title", null)
            views.setTextViewText(R.id.today_title, title ?: "School365ai")

            val lines = listOf(R.id.today_line1, R.id.today_line2, R.id.today_line3, R.id.today_line4)
            lines.forEachIndexed { index, viewId ->
                val text = if (title == null && index == 0) {
                    "Open the app to see your day"
                } else {
                    widgetData.getString("today_line${index + 1}", "") ?: ""
                }
                views.setTextViewText(viewId, text)
                views.setViewVisibility(viewId, if (text.isEmpty()) View.GONE else View.VISIBLE)
            }

            val asOf = widgetData.getString("today_as_of", "") ?: ""
            views.setTextViewText(R.id.today_as_of, asOf)
            views.setViewVisibility(R.id.today_as_of, if (asOf.isEmpty()) View.GONE else View.VISIBLE)

            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

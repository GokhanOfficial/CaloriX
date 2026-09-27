package com.calorix.calorix.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import com.calorix.calorix.R

/**
 * Haftalık 7 günlük kalori grafiği widget'ı.
 *
 * Çubuk yükseklikleri Dart tarafında hesaplanmış ve normalize edilmiş bir
 * dizi olarak gelir (`weekly.values`, JSON int[]). Burada yalnızca ölçeklenir
 * ve çizilir; hedef çizgisi de `weekly.target` ile verilir.
 */
class WeeklyWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { id ->
            appWidgetManager.updateAppWidget(id, buildViews(context, id))
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == DailyWidgetProvider.ACTION_REFRESH) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, WeeklyWidgetProvider::class.java)
            )
            if (ids.isNotEmpty()) onUpdate(context, manager, ids)
        }
    }

    private fun buildViews(context: Context, widgetId: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_weekly)
        val manager = AppWidgetManager.getInstance(context)

        views.setOnClickPendingIntent(
            R.id.widget_root,
            openAppIntent(context, widgetId),
        )

        views.setTextViewText(R.id.widget_title, WidgetData.weeklyTitle(context))

        val signedOut = WidgetData.state(context) != WidgetData.STATE_READY
        if (signedOut) {
            views.setViewVisibility(R.id.widget_chart, View.GONE)
            views.setViewVisibility(R.id.widget_message, View.VISIBLE)
            views.setTextViewText(
                R.id.widget_message,
                if (WidgetData.state(context) == WidgetData.STATE_SIGNED_OUT) {
                    WidgetData.signedOut(context)
                } else {
                    WidgetData.staleHint(context)
                },
            )
            manager.updateAppWidget(widgetId, views)
            return views
        }

        views.setViewVisibility(R.id.widget_message, View.GONE)
        views.setViewVisibility(R.id.widget_chart, View.VISIBLE)

        val values = WidgetData.weeklyValues(context)
        val labels = WidgetData.weeklyLabels(context)
        val target = WidgetData.weeklyTarget(context)

        // Ölçek: hedef çizgisi ve en yüksek çubuk birlikte görünsün. Hedef 0
        // ise yalnızca en yüksek çubuk ölçeklenir. Hepsi 0 ise boş bırakılır.
        val peak = maxOf(target, values.maxOrNull() ?: 0, 1)
        val chartHeightPx = context.resources.getDimensionPixelSize(R.dimen.widget_chart_height)
        val barIds = intArrayOf(
            R.id.widget_bar_0, R.id.widget_bar_1, R.id.widget_bar_2, R.id.widget_bar_3,
            R.id.widget_bar_4, R.id.widget_bar_5, R.id.widget_bar_6,
        )

        // RemoteViews çalışma zamanında layout parametresi değiştiremez; yalnızca
        // API 31+ üzerinde `setViewLayoutHeight` ile yükseklik atanabilir. Bu
        // eşiğin altında çubuklar ölçeklenemediği için grafik yerine özet
        // metinleri gösterilir (nadir cihazlar; çökme yerine sadeleştirme).
        val scalable = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S

        for (i in barIds.indices) {
            val value = values.getOrElse(i) { 0 }
            val fraction = (value.toFloat() / peak.toFloat()).coerceIn(0f, 1f)
            // Kayıt olmayan gün görünmez olmasın diye taban yükseklik bırakılır.
            val barHeight = if (value > 0) {
                (chartHeightPx * fraction).toInt().coerceAtLeast(MIN_BAR_PX)
            } else {
                MIN_BAR_PX
            }
            // Genişlik sabit (0), yalnızca yükseklik ölçeklenir.
            if (scalable) views.setViewLayoutHeight(barIds[i], barHeight.toFloat(), 0)
            val isToday = i == WidgetData.weeklyTodayIndex(context)
            views.setInt(
                barIds[i],
                "setBackgroundColor",
                if (isToday) todayColor(context) else barColor(context),
            )
            views.setTextViewText(labelId(i), labels.getOrElse(i) { "" })
        }

        if (!scalable) {
            // Ölçeklenemeyen cihazlarda grafik yerine günlük değer listesi.
            views.setViewVisibility(R.id.widget_chart, View.GONE)
            views.setViewVisibility(R.id.widget_values, View.VISIBLE)
            views.setTextViewText(
                R.id.widget_values,
                values.mapIndexed { idx, v ->
                    val label = labels.getOrElse(idx) { "" }
                    if (target > 0) "$label $v/$target" else "$label $v"
                }.joinToString("   "),
            )
        } else {
            views.setViewVisibility(R.id.widget_values, View.GONE)
        }

        // Alt bilgi: ortalama ve hedefte gün sayısı.
        bindFooter(context, views)

        manager.updateAppWidget(widgetId, views)
        return views
    }

    private fun bindFooter(context: Context, views: RemoteViews) {
        var footerVisible = false

        if (WidgetData.weeklyShowAvg(context)) {
            val avgLabel = WidgetData.avgLabel(context)
            val avg = WidgetData.weeklyAvg(context)
            views.setViewVisibility(R.id.widget_avg, View.VISIBLE)
            views.setTextViewText(
                R.id.widget_avg,
                if (avgLabel.isBlank()) "$avg" else "$avg $avgLabel",
            )
            footerVisible = true
        } else {
            views.setViewVisibility(R.id.widget_avg, View.GONE)
        }

        if (WidgetData.weeklyShowOnTarget(context)) {
            val onTargetLabel = WidgetData.onTargetLabel(context)
            val days = WidgetData.weeklyOnTarget(context)
            views.setViewVisibility(R.id.widget_on_target, View.VISIBLE)
            views.setTextViewText(
                R.id.widget_on_target,
                if (onTargetLabel.isBlank()) "$days" else "$days $onTargetLabel",
            )
            footerVisible = true
        } else {
            views.setViewVisibility(R.id.widget_on_target, View.GONE)
        }

        views.setViewVisibility(
            R.id.widget_footer,
            if (footerVisible) View.VISIBLE else View.GONE,
        )
    }

    private fun openAppIntent(context: Context, widgetId: Int): PendingIntent {
        val launch = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?: Intent(Intent.ACTION_MAIN)
        return PendingIntent.getActivity(
            context, widgetId, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** Tema uyumlu çubuk rengi — koyu temada daha açık ton gerekir. */
    private fun barColor(context: Context): Int {
        val night = (context.resources.configuration.uiMode and
            android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        return if (night) Color.parseColor("#7C6CF5") else Color.parseColor("#4F46E5")
    }

    private fun todayColor(context: Context): Int {
        val night = (context.resources.configuration.uiMode and
            android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        return if (night) Color.parseColor("#A5B4FC") else Color.parseColor("#F59E0B")
    }

    private companion object {
        /** Kayıt girilmemiş günlerin de görünür kalması için taban yükseklik. */
        const val MIN_BAR_PX = 3
    }
}

/** Gün etiketi view id'leri — 7 çubuk için sabit eşleme. */
private fun labelId(index: Int): Int = when (index) {
    0 -> R.id.widget_label_0
    1 -> R.id.widget_label_1
    2 -> R.id.widget_label_2
    3 -> R.id.widget_label_3
    4 -> R.id.widget_label_4
    5 -> R.id.widget_label_5
    else -> R.id.widget_label_6
}

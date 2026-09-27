package com.calorix.calorix.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.calorix.calorix.R

/**
 * Günlük özet ana ekran widget'ı.
 *
 * Tüm veri Dart tarafı tarafından önceden hesaplanmış ve `flutter` adlı
 * SharedPreferences'a yazılmıştır (bkz. `WidgetData`). Bu sınıf yalnızca
 * okur ve çizer; ağ çağrısı, hesap veya Supabase erişimi **yoktur**.
 *
 * Üç durum vardır:
 *  - `ready`      → tam özet
 *  - `signedOut`  → giriş yap uyarısı
 *  - `noConfig`   → ilk kurulumda veri yok
 *
 * Ek olarak veri 6 saatten eskiyse "bayat" ipucu gösterilir.
 */
class DailyWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { id ->
            appWidgetManager.updateAppWidget(id, buildViews(context, id))
        }
    }

    /** Veri değişti: Dart tarafı bu yayını yapar, tüm örnekler tazelenir. */
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                android.content.ComponentName(context, DailyWidgetProvider::class.java)
            )
            if (ids.isNotEmpty()) onUpdate(context, manager, ids)
        }
    }

    private fun buildViews(context: Context, widgetId: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_daily)
        val manager = AppWidgetManager.getInstance(context)

        // Widget'ın kendisine tıklanınca uygulamayı aç (şeffaf PendingIntent).
        views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context, widgetId))

        when (WidgetData.state(context)) {
            WidgetData.STATE_READY -> bindReady(context, views)
            WidgetData.STATE_SIGNED_OUT -> bindMessage(
                context, views,
                WidgetData.dailyTitle(context),
                WidgetData.signedOut(context),
            )
            else -> bindMessage(
                context, views,
                WidgetData.dailyTitle(context),
                WidgetData.staleHint(context),
            )
        }

        // Ayarlar düğmesi → uygulamadaki "Widget ayarları" diyaloğu.
        views.setOnClickPendingIntent(
            R.id.widget_settings_button,
            manageConfigIntent(context, widgetId),
        )

        manager.updateAppWidget(widgetId, views)
        return views
    }

    private fun bindReady(context: Context, views: RemoteViews) {
        val stale = WidgetData.isStale(context)
        views.setTextViewText(R.id.widget_title, WidgetData.dailyTitle(context))
        views.setViewVisibility(R.id.widget_body, android.view.View.VISIBLE)

        val target = WidgetData.target(context)
        val consumed = WidgetData.calories(context)

        // "1234 / 2000 kcal" — hedef 0 isa yalnızca tüketilen gösterilir.
        val kcalLabel = WidgetData.kcalLabel(context)
        views.setTextViewText(
            R.id.widget_calories,
            if (target > 0) {
                "$consumed / $target $kcalLabel"
            } else {
                "$consumed $kcalLabel"
            },
        )

        // İlerleme çubuğu: permille 0..1000, hedef 0 ise gizlenir.
        if (target > 0) {
            views.setViewVisibility(R.id.widget_progress, android.view.View.VISIBLE)
            views.setProgressBar(R.id.widget_progress, 1000, WidgetData.permille(context), false)
        } else {
            views.setViewVisibility(R.id.widget_progress, android.view.View.GONE)
        }

        // "423 kalan" — tüketilen hedefi aştıysa "kalan" yerine aşım gösterilir.
        val remaining = WidgetData.remaining(context)
        views.setTextViewText(
            R.id.widget_remaining,
            if (remaining > 0) {
                "$remaining ${WidgetData.remainingLabel(context)}"
            } else if (target > 0 && consumed > target) {
                "${consumed - target} ${WidgetData.remainingLabel(context)}"
            } else {
                ""
            },
        )

        bindMacros(context, views)
        bindWater(context, views)

        // Kilo satırı yalnızca veri + ayar varsa.
        val weightText = WidgetData.weightText(context)
        if (WidgetData.showWeight(context) && weightText.isNotBlank()) {
            views.setViewVisibility(R.id.widget_weight, android.view.View.VISIBLE)
            views.setTextViewText(R.id.widget_weight, weightText)
        } else {
            views.setViewVisibility(R.id.widget_weight, android.view.View.GONE)
        }

        // Teşvik metni yalnızca dolu değilse ve veri bayat değilse.
        val enc = WidgetData.encouragement(context)
        if (!stale && enc.isNotBlank()) {
            views.setViewVisibility(R.id.widget_encouragement, android.view.View.VISIBLE)
            views.setTextViewText(R.id.widget_encouragement, enc)
        } else {
            views.setViewVisibility(R.id.widget_encouragement, android.view.View.GONE)
        }

        if (stale) {
            views.setViewVisibility(R.id.widget_stale, android.view.View.VISIBLE)
            views.setTextViewText(R.id.widget_stale, WidgetData.staleHint(context))
        } else {
            views.setViewVisibility(R.id.widget_stale, android.view.View.GONE)
        }

        // Hızlı ekle düğmesi.
        val quickAdd = WidgetData.quickAddLabel(context)
        if (quickAdd.isNotBlank()) {
            views.setViewVisibility(R.id.widget_quick_add, android.view.View.VISIBLE)
            views.setTextViewText(R.id.widget_quick_add, quickAdd)
        } else {
            views.setViewVisibility(R.id.widget_quick_add, android.view.View.GONE)
        }
    }

    private fun bindMacros(context: Context, views: RemoteViews) {
        if (!WidgetData.showMacros(context)) {
            views.setViewVisibility(R.id.widget_macros, android.view.View.GONE)
            return
        }
        views.setViewVisibility(R.id.widget_macros, android.view.View.VISIBLE)
        // Etiketler (P/K/Y) kaynak dosyada sabittir; sayılar Dart'tan gelir.
        views.setTextViewText(
            R.id.widget_protein, macroText(WidgetData.protein(context), WidgetData.proteinTarget(context))
        )
        views.setTextViewText(
            R.id.widget_carbs, macroText(WidgetData.carbs(context), WidgetData.carbsTarget(context))
        )
        views.setTextViewText(
            R.id.widget_fat, macroText(WidgetData.fat(context), WidgetData.fatTarget(context))
        )
    }

    /** "95/120" gibi özetsiz metin; hedef 0 isa yalnızca değer. */
    private fun macroText(value: Int, target: Int): String =
        if (target > 0) "$value/$target" else value.toString()

    private fun bindWater(context: Context, views: RemoteViews) {
        if (!WidgetData.showWater(context)) {
            views.setViewVisibility(R.id.widget_water, android.view.View.GONE)
            return
        }
        val water = WidgetData.water(context)
        val waterTarget = WidgetData.waterTarget(context)
        views.setViewVisibility(R.id.widget_water, android.view.View.VISIBLE)
        views.setTextViewText(
            R.id.widget_water,
            if (waterTarget > 0) "$water / $waterTarget ml" else "$water ml",
        )
    }

    private fun bindMessage(context: Context, views: RemoteViews, title: String, body: String) {
        views.setTextViewText(R.id.widget_title, title)
        views.setViewVisibility(R.id.widget_body, android.view.View.GONE)
        views.setViewVisibility(R.id.widget_message, android.view.View.VISIBLE)
        views.setTextViewText(R.id.widget_message, body)
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

    private fun manageConfigIntent(context: Context, widgetId: Int): PendingIntent {
        // Yapılandırma ekranı (ACTION_APPWIDGET_CONFIGURE) yok: görünürlük
        // ayarları uygulamadaki "Widget ayarları" diyaloğundan yönetilir.
        // Bu düğme o diyaloğu açan derin bağlantıyı tetikler.
        val intent = Intent(
            Intent.ACTION_VIEW,
            android.net.Uri.parse("$WIDGET_SETTINGS_URI"),
        )
        return PendingIntent.getActivity(
            context, widgetId, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    companion object {
        /** Dart tarafı bu yayını yapar → widget'lar tazelenir. */
        const val ACTION_REFRESH = "com.calorix.app.action.WIDGET_REFRESH"

        /**
         * Ayarlar diyaloğunu açan derin bağlantı.
         *
         * `android:exported` olmayan activity'ye dışarıdan Intent atılamaz;
         * ancak launcher, widget üzerinden başlatılan PendingIntent'i
         * uygulamanın kendi imzasıyla çalıştırır. `MainActivity` bu şemayı
         * `app.dart` tarafında `GoRouter` üzerinden karşılar.
         */
        private const val WIDGET_SETTINGS_URI = "calorix://widget/settings"
    }
}

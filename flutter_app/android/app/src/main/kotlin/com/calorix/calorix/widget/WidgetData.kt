package com.calorix.calorix.widget

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import kotlin.math.roundToInt

/**
 * Dart↔Kotlin veri kanalı okuyucu.
 *
 * Anahtar sözleşmesi `lib/core/widgets/widget_snapshot.dart` içindeki
 * `WidgetKeys` sınıfıyla **birebir** aynı olmalıdır. Dart tarafı her veri
 * değişiminde önceden hesaplanmış, önceden yuvarlanmış, önceden çevrilmiş
 * değerleri SharedPreferences'a yazar; burada hiçbir hesap yapılmaz, sadece
 * okunur ve güvenli varsayılana düşülür.
 *
 * Hiçbir anahtar eksikse veya bozuksa ilgili alan güvenli varsayılana döner —
 * native taraf asla `null` beklememeli, aksi halde widget çizimi patlar.
 */
internal object WidgetData {

    // --- Anahtarlar (WidgetKeys ile aynı) --------------------------------
    private const val STATE = "widget.state"
    private const val DATE = "widget.date"
    private const val UPDATED_AT = "widget.updatedAt"
    private const val LOCALE = "widget.locale"

    private const val D_CALORIES = "daily.calories"
    private const val D_TARGET = "daily.target"
    private const val D_REMAINING = "daily.remaining"
    private const val D_PERMILLE = "daily.progressPermille"
    private const val D_PROTEIN = "daily.protein"
    private const val D_PROTEIN_T = "daily.proteinTarget"
    private const val D_CARBS = "daily.carbs"
    private const val D_CARBS_T = "daily.carbsTarget"
    private const val D_FAT = "daily.fat"
    private const val D_FAT_T = "daily.fatTarget"
    private const val D_WATER = "daily.water"
    private const val D_WATER_T = "daily.waterTarget"
    private const val D_WEIGHT_TEXT = "daily.weightText"
    private const val D_HAS_MEALS = "daily.hasMeals"
    private const val D_ENC_TEXT = "daily.encouragementText"
    private const val D_SHOW_MACROS = "daily.showMacros"
    private const val D_SHOW_WATER = "daily.showWater"
    private const val D_SHOW_WEIGHT = "daily.showWeight"

    private const val W_VALUES = "weekly.values"
    private const val W_LABELS = "weekly.labels"
    private const val W_TODAY_IDX = "weekly.todayIndex"
    private const val W_TARGET = "weekly.target"
    private const val W_AVG = "weekly.avg"
    private const val W_ON_TARGET = "weekly.daysOnTarget"
    private const val W_SHOW_AVG = "weekly.showAvg"
    private const val W_SHOW_ON_TARGET = "weekly.showDaysOnTarget"

    private const val S_DAILY_TITLE = "str.dailyTitle"
    private const val S_WEEKLY_TITLE = "str.weeklyTitle"
    private const val S_SIGNED_OUT = "str.signedOut"
    private const val S_STALE = "str.staleHint"
    private const val S_REMAINING = "str.remaining"
    private const val S_KCAL = "str.kcal"
    private const val S_AVG = "str.avg"
    private const val S_ON_TARGET = "str.onTarget"
    private const val S_QUICK_ADD = "str.quickAdd"

    /** Veri yaşı eşiği: bundan eski snapshot "bayat" sayılır. */
    const val STALE_AFTER_MS = 6 * 60 * 60 * 1000L // 6 saat

    const val STATE_READY = "ready"
    const val STATE_SIGNED_OUT = "signedOut"
    const val STATE_NO_CONFIG = "noConfig"

    /** Tüm anahtarları tip güvenli okuyan tek nokta. */
    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences("flutter", Context.MODE_PRIVATE)

    fun state(context: Context): String = str(context, STATE, STATE_NO_CONFIG).let {
        if (it == STATE_READY || it == STATE_SIGNED_OUT || it == STATE_NO_CONFIG) it else STATE_NO_CONFIG
    }

    fun date(context: Context): String = str(context, DATE, "")

    fun locale(context: Context): String = str(context, LOCALE, "en")

    fun updatedAt(context: Context): Long = long(context, UPDATED_AT, 0L)

    /** Snapshot yaşlı mı? (Gelecek tarihli veri de bayat sayılır.) */
    fun isStale(context: Context, nowMs: Long = System.currentTimeMillis()): Boolean {
        val updated = updatedAt(context)
        if (updated <= 0L) return true
        return nowMs - updated > STALE_AFTER_MS
    }

    fun calories(context: Context) = int(context, D_CALORIES, 0)
    fun target(context: Context) = int(context, D_TARGET, 0)
    fun remaining(context: Context) = int(context, D_REMAINING, 0)

    /** 0..1000 aralığına kırpılmış ilerleme (Dart tarafı da kırpar; savunma). */
    fun permille(context: Context): Int = int(context, D_PERMILLE, 0).coerceIn(0, 1000)

    fun protein(context: Context) = int(context, D_PROTEIN, 0)
    fun proteinTarget(context: Context) = int(context, D_PROTEIN_T, 0)
    fun carbs(context: Context) = int(context, D_CARBS, 0)
    fun carbsTarget(context: Context) = int(context, D_CARBS_T, 0)
    fun fat(context: Context) = int(context, D_FAT, 0)
    fun fatTarget(context: Context) = int(context, D_FAT_T, 0)
    fun water(context: Context) = int(context, D_WATER, 0)
    fun waterTarget(context: Context) = int(context, D_WATER_T, 0)
    fun weightText(context: Context): String = str(context, D_WEIGHT_TEXT, "")
    fun encouragement(context: Context): String = str(context, D_ENC_TEXT, "")

    fun hasMeals(context: Context) = bool(context, D_HAS_MEALS, false)
    fun showMacros(context: Context) = bool(context, D_SHOW_MACROS, true)
    fun showWater(context: Context) = bool(context, D_SHOW_WATER, true)
    fun showWeight(context: Context) = bool(context, D_SHOW_WEIGHT, false)

    fun weeklyValues(context: Context): IntArray = intArray(context, W_VALUES, 7)
    fun weeklyLabels(context: Context): Array<String> = stringArray(context, W_LABELS, 7)
    fun weeklyTodayIndex(context: Context) = int(context, W_TODAY_IDX, 6).coerceIn(0, 6)
    fun weeklyTarget(context: Context) = int(context, W_TARGET, 0)
    fun weeklyAvg(context: Context) = int(context, W_AVG, 0)
    fun weeklyOnTarget(context: Context) = int(context, W_ON_TARGET, 0)
    fun weeklyShowAvg(context: Context) = bool(context, W_SHOW_AVG, true)
    fun weeklyShowOnTarget(context: Context) = bool(context, W_SHOW_ON_TARGET, true)

    fun dailyTitle(context: Context) = str(context, S_DAILY_TITLE, "")
    fun weeklyTitle(context: Context) = str(context, S_WEEKLY_TITLE, "")
    fun signedOut(context: Context) = str(context, S_SIGNED_OUT, "")
    fun staleHint(context: Context) = str(context, S_STALE, "")
    fun remainingLabel(context: Context) = str(context, S_REMAINING, "")
    fun kcalLabel(context: Context) = str(context, S_KCAL, "kcal")
    fun avgLabel(context: Context) = str(context, S_AVG, "")
    fun onTargetLabel(context: Context) = str(context, S_ON_TARGET, "")
    fun quickAddLabel(context: Context) = str(context, S_QUICK_ADD, "")

    // --- Güvenli okuma yardımcıları ---------------------------------------

    private fun str(context: Context, key: String, fallback: String): String =
        runCatching { prefs(context).getString(key, fallback) }.getOrNull() ?: fallback

    private fun int(context: Context, key: String, fallback: Int): Int = runCatching {
        prefs(context).getInt(key, fallback)
    }.getOrElse {
        // Dart tarafı bazı alanlarda double yazmış olabilir (örn. NaN sonrası
        // yazılan değer). Type castException'ı yutulur.
        runCatching {
            val d = prefs(context).getFloat(key, fallback.toFloat())
            if (d.isNaN() || d.isInfinite()) fallback else d.roundToInt()
        }.getOrDefault(fallback)
    }

    private fun long(context: Context, key: String, fallback: Long): Long = runCatching {
        prefs(context).getLong(key, fallback)
    }.getOrElse {
        runCatching { prefs(context).getFloat(key, fallback.toFloat()).toLong() }
            .getOrDefault(fallback)
    }

    private fun bool(context: Context, key: String, fallback: Boolean): Boolean = runCatching {
        prefs(context).getBoolean(key, fallback)
    }.getOrDefault(fallback)

    /** `JSON int[]` → sabit boyutlu dizi. Bozuk/eksikse sıfırlarla dolar. */
    private fun intArray(context: Context, key: String, size: Int): IntArray {
        val raw = runCatching { str(context, key, "") }.getOrDefault("")
        val out = IntArray(size)
        if (raw.isBlank()) return out
        runCatching {
            val arr = JSONArray(raw)
            for (i in 0 until minOf(arr.length(), size)) out[i] = arr.optInt(i, 0)
        }
        return out
    }

    /** `JSON String[]` → sabit boyutlu dizi. */
    private fun stringArray(context: Context, key: String, size: Int): Array<String> {
        val raw = runCatching { str(context, key, "") }.getOrDefault("")
        val out = arrayOfNulls<String>(size)
        if (raw.isBlank()) return Array(size) { "" }
        runCatching {
            val arr = JSONArray(raw)
            for (i in 0 until minOf(arr.length(), size)) out[i] = arr.optString(i, "")
        }
        return Array(size) { out[it] ?: "" }
    }
}

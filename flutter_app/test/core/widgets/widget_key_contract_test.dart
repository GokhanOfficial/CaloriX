import 'dart:io';

import 'package:calorix/core/widgets/widget_bridge.dart';
import 'package:calorix/core/widgets/widget_settings.dart';
import 'package:calorix/core/widgets/widget_snapshot.dart';
import 'package:calorix/core/widgets/widget_strings.dart';
import 'package:calorix/data/repositories/diary_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dart (`WidgetKeys`) ↔ Kotlin (`WidgetData.kt`) anahtar sözleşmesi
/// tutarlılık testi.
///
/// ## Neden bu test var
///
/// İki taraf ayrı dosyalarda tanımlıdır ve derleyici aralarında bağ yoktur:
/// bir anahtar Dart'ta yeniden adlandırılıp Kotlin'de eski adıyla kalırsa
/// **derleme hâlâ yeşildir**; hata yalnızca cihazda, widget "veri yok"
/// görünümü olarak ortaya çıkar. Önceki iki turda bu katmanda iki gerçek hata
/// çıkmıştı (Double bit-deseni okuması, `HomeWidget.updateWidget` sınıf
/// çözümlemesi) — ikisi de test edilebilir bir sözleşmeye bağlanmamıştı.
///
/// Bu test `WidgetData.kt` dosyasını **metin olarak okur** ve sabitlerini
/// Dart `WidgetKeys` ile karşılaştırır. Kotlin tarafında anahtar eklendiği /
/// yeniden adlandırıldığı anda `flutter test` kırmızıya döner.
///
/// ## Neden `lib/` dışı dosya okunuyor
///
/// `flutter test` çalışma dizini `flutter_app/`'dir; yol göreli verilir.
/// CI'da aynı komut aynı dizinde çalıştığı için test tekrarlanabilirdir.
void main() {
  final kotlinFile = File(
    'android/app/src/main/kotlin/com/calorix/calorix/widget/WidgetData.kt',
  );

  /// `private const val D_CALORIES = "daily.calories"` satırlarından
  /// (sabit adı, değeri) çiftlerini toplar.
  Map<String, String> parseKotlinKeys(String source) {
    final result = <String, String>{};
    final pattern = RegExp(
      r'(?:private|internal)?\s*const\s+val\s+(\w+)\s*=\s*"([^"]*)"',
    );
    for (final match in pattern.allMatches(source)) {
      result[match.group(1)!] = match.group(2)!;
    }
    return result;
  }

  /// Testlerde kullanılan asgari metin paketi (çeviri bağımlılığı yok).
  const testStrings = WidgetStrings(
    dailyTitle: 'Günlük',
    weeklyTitle: 'Haftalık',
    remaining: 'kalan',
    kcal: 'kcal',
    avg: 'ort.',
    onTarget: 'hedefte',
    quickAdd: 'Ekle',
    signedOut: 'Giriş yap',
    staleHint: 'Eski',
    encMorning: 'sabah',
    encAfternoon: 'ogleden',
    encEvening: 'aksam',
    nudgeTitle: 'nudge',
    nudgeBody: 'nudge govde',
  );

  test('WidgetData.kt dosyası bulunur (yol kayması testi yakalar)', () {
    expect(
      kotlinFile.existsSync(),
      isTrue,
      reason: 'Kotlin widget okuyucusu bulunamadı: ${kotlinFile.path}',
    );
  });

  test('Dart WidgetKeys ile Kotlin sabitleri birebir aynı', () {
    final source = kotlinFile.readAsStringSync();
    final kotlin = parseKotlinKeys(source);
    expect(kotlin, isNotEmpty, reason: 'Kotlin sabitleri ayrıştırılamadı');

    // Kotlin sabit adı → Dart WidgetKeys alan adı.
    // `D_` öneki `d*`, `W_` öneki `w*`, `S_` öneki `s*` demektir.
    const kotlinToDart = <String, String>{
      'STATE': 'state',
      'DATE': 'date',
      'UPDATED_AT': 'updatedAt',
      'LOCALE': 'locale',
      'D_CALORIES': 'dCalories',
      'D_TARGET': 'dTarget',
      'D_REMAINING': 'dRemaining',
      'D_PERMILLE': 'dPermille',
      'D_PROTEIN': 'dProtein',
      'D_PROTEIN_T': 'dProteinT',
      'D_CARBS': 'dCarbs',
      'D_CARBS_T': 'dCarbsT',
      'D_FAT': 'dFat',
      'D_FAT_T': 'dFatT',
      'D_WATER': 'dWater',
      'D_WATER_T': 'dWaterT',
      'D_WEIGHT_TEXT': 'dWeightText',
      'D_HAS_MEALS': 'dHasMeals',
      'D_ENC_TEXT': 'dEncText',
      'D_SHOW_MACROS': 'dShowMacros',
      'D_SHOW_WATER': 'dShowWater',
      'D_SHOW_WEIGHT': 'dShowWeight',
      'W_VALUES': 'wValues',
      'W_LABELS': 'wLabels',
      'W_TODAY_IDX': 'wTodayIdx',
      'W_TARGET': 'wTarget',
      'W_AVG': 'wAvg',
      'W_ON_TARGET': 'wOnTarget',
      'W_SHOW_AVG': 'wShowAvg',
      'W_SHOW_ON_TARGET': 'wShowOnTarget',
      'S_DAILY_TITLE': 'sDailyTitle',
      'S_WEEKLY_TITLE': 'sWeeklyTitle',
      'S_SIGNED_OUT': 'sSignedOut',
      'S_STALE': 'sStale',
      'S_REMAINING': 'sRemaining',
      'S_KCAL': 'sKcal',
      'S_AVG': 'sAvg',
      'S_ON_TARGET': 'sOnTarget',
      'S_QUICK_ADD': 'sQuickAdd',
    };

    // Dart tarafındaki gerçek değerler (yansıma yerine açık liste — bir alan
    // yeniden adlandırılırsa derleyici değil, bu liste kırmızıya döner).
    final dartKeys = <String, String>{
      'state': WidgetKeys.state,
      'date': WidgetKeys.date,
      'updatedAt': WidgetKeys.updatedAt,
      'locale': WidgetKeys.locale,
      'dCalories': WidgetKeys.dCalories,
      'dTarget': WidgetKeys.dTarget,
      'dRemaining': WidgetKeys.dRemaining,
      'dPermille': WidgetKeys.dPermille,
      'dProtein': WidgetKeys.dProtein,
      'dProteinT': WidgetKeys.dProteinT,
      'dCarbs': WidgetKeys.dCarbs,
      'dCarbsT': WidgetKeys.dCarbsT,
      'dFat': WidgetKeys.dFat,
      'dFatT': WidgetKeys.dFatT,
      'dWater': WidgetKeys.dWater,
      'dWaterT': WidgetKeys.dWaterT,
      'dWeightText': WidgetKeys.dWeightText,
      'dHasMeals': WidgetKeys.dHasMeals,
      'dEncText': WidgetKeys.dEncText,
      'dShowMacros': WidgetKeys.dShowMacros,
      'dShowWater': WidgetKeys.dShowWater,
      'dShowWeight': WidgetKeys.dShowWeight,
      'wValues': WidgetKeys.wValues,
      'wLabels': WidgetKeys.wLabels,
      'wTodayIdx': WidgetKeys.wTodayIdx,
      'wTarget': WidgetKeys.wTarget,
      'wAvg': WidgetKeys.wAvg,
      'wOnTarget': WidgetKeys.wOnTarget,
      'wShowAvg': WidgetKeys.wShowAvg,
      'wShowOnTarget': WidgetKeys.wShowOnTarget,
      'sDailyTitle': WidgetKeys.sDailyTitle,
      'sWeeklyTitle': WidgetKeys.sWeeklyTitle,
      'sSignedOut': WidgetKeys.sSignedOut,
      'sStale': WidgetKeys.sStale,
      'sRemaining': WidgetKeys.sRemaining,
      'sKcal': WidgetKeys.sKcal,
      'sAvg': WidgetKeys.sAvg,
      'sOnTarget': WidgetKeys.sOnTarget,
      'sQuickAdd': WidgetKeys.sQuickAdd,
    };

    final mismatches = <String>[];
    for (final entry in kotlinToDart.entries) {
      final dartField = entry.value;
      final kotlinValue = kotlin[entry.key];
      if (kotlinValue == null) {
        mismatches.add(
          'Kotlin tarafında ${entry.key} sabiti yok '
          '(Dart: $dartField = "${dartKeys[dartField]}")',
        );
        continue;
      }
      final dartValue = dartKeys[dartField];
      if (dartValue == null) {
        mismatches.add('Dart tarafında WidgetKeys.$dartField alanı yok');
        continue;
      }
      if (kotlinValue != dartValue) {
        mismatches.add(
          'DEĞER AYRIŞTI ${entry.key}: Kotlin="$kotlinValue" '
          '≠ Dart WidgetKeys.$dartField="$dartValue"',
        );
      }
    }
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));

    // Ters yön: Dart tarafında bir anahtar **eklenmiş** ama Kotlin tarafı
    // güncellenmemişse (sözleşmeye yeni anahtar eklendi, native okuyucu
    // güncellenmedi) sözleşme sessizce yarı kalır. Bu yön de kilitlenir.
    const mappedKotlinNames = <String>{
      'STATE',
      'DATE',
      'UPDATED_AT',
      'LOCALE',
      'D_CALORIES',
      'D_TARGET',
      'D_REMAINING',
      'D_PERMILLE',
      'D_PROTEIN',
      'D_PROTEIN_T',
      'D_CARBS',
      'D_CARBS_T',
      'D_FAT',
      'D_FAT_T',
      'D_WATER',
      'D_WATER_T',
      'D_WEIGHT_TEXT',
      'D_HAS_MEALS',
      'D_ENC_TEXT',
      'D_SHOW_MACROS',
      'D_SHOW_WATER',
      'D_SHOW_WEIGHT',
      'W_VALUES',
      'W_LABELS',
      'W_TODAY_IDX',
      'W_TARGET',
      'W_AVG',
      'W_ON_TARGET',
      'W_SHOW_AVG',
      'W_SHOW_ON_TARGET',
      'S_DAILY_TITLE',
      'S_WEEKLY_TITLE',
      'S_SIGNED_OUT',
      'S_STALE',
      'S_REMAINING',
      'S_KCAL',
      'S_AVG',
      'S_ON_TARGET',
      'S_QUICK_ADD',
    };
    // Dart tarafında sözleşmeye eklenen ama eşleme tablosunda olmayan alan:
    // `WidgetKeys.stateValues` dolu bir listedir, dolayısıyla yeni alan
    // burada görünür. (Liste uzunluğu da eşleme tablosuyla eşleşmeli.)
    expect(
      WidgetKeys.stateValues.length,
      mappedKotlinNames.length,
      reason: 'WidgetKeys.stateValues ile Kotlin eşleme tablosu farklı '
          'sayıda anahtar içeriyor — bir taraf güncellenmemiş',
    );
  });

  test('hiçbir anahtar diğer tarafta karşılıksız kalmaz', () {
    final kotlin = parseKotlinKeys(kotlinFile.readAsStringSync());
    // `WidgetData.kt` içindeki anahtar dışı sabitler: prefs dosya adı, bayrak
    // öneki, bayat eşik, durum değerleri, boyut parametreleri.
    const nonKeyConstants = <String>{
      'PREFS',
      'DOUBLE_FLAG_PREFIX',
      'STALE_AFTER_MS',
      'STATE_READY',
      'STATE_SIGNED_OUT',
      'STATE_NO_CONFIG',
    };
    final keyLike = <String, String>{
      for (final e in kotlin.entries)
        if (e.value.contains('.')) e.key: e.value,
    };
    final dartKeyValues = WidgetKeys.stateValues.toSet();

    for (final entry in keyLike.entries) {
      if (nonKeyConstants.contains(entry.key)) continue;
      expect(
        dartKeyValues,
        contains(entry.value),
        reason: 'Kotlin anahtarı "${entry.value}" (${entry.key}) '
            'WidgetKeys tarafında karşılıksız',
      );
    }
  });

  test('tip sözleşmesi: Dart tüm sayıları double yazıyor, Kotlin bit çözüyor', () {    // `home_widget` `Double` değerleri `putLong(rawLongBits)` + bayrakla
    // saklıyor. `WidgetBridge.publish` her sayıyı `saveDouble` ile yazıyor
    // (`num` → `toDouble()`), yani native tarafın `Long` dalında
    // `Double.fromBits` kullanması **zorunlu**. Bu iki tur önce iki gerçek
    // hatanın kaynağıydı; sözleşme metniyle kilitleniyor.
    final source = kotlinFile.readAsStringSync();
    expect(
      source,
      contains('home_widget.double.'),
      reason: 'Kotlin tarafı Double bayrağını tanımıyor — '
          'home_widget sayıları yanlış okunur',
    );
    expect(
      source,
      contains('Double.fromBits'),
      reason: 'Kotlin tarafı Long bit desenini çözmüyor',
    );
    // Aynı anda getInt/getLong ile okumak ClassCastException fırlatır:
    // `p.all[key]` üzerinden okunmalı.
    expect(
      source,
      contains('p.all[key]'),
      reason: 'Kotlin tarafı prefs.all üzerinden okumuyor — '
          'tip zorlama istisnası fırlatabilir',
    );
  });

  test('durum değerleri iki tarafta aynı', () {
    expect(WidgetBridge.stateReady, 'ready');
    expect(WidgetBridge.stateSignedOut, 'signedOut');
    expect(WidgetBridge.stateNoConfig, 'noConfig');
    // Kotlin tarafı `STATE_READY`/`STATE_SIGNED_OUT`/`STATE_NO_CONFIG`
    // olarak aynı üç değeri tanımlıyor (WidgetData.kt:88-90).
  });

  test('tazeleme yayını: provider sınıf adı ve aksiyon sabiti eşleşir', () {
    // 1) `HomeWidgetSave.update` **paket öneki olmadan** sınıf adı
    // vermeli. `name` verilirse `home_widget` `"$packageName.$name"` arar
    // (`HomeWidgetPlugin.kt:269`) ve `com.calorix.app.DailyWidgetProvider`
    // bulunamaz → ClassNotFoundException → hiçbir widget tazelenmez.
    // Test, kaynağın `name:` anahtarını **kullanmadığını** doğrular.
    final bridgeSource =
        File('lib/core/widgets/widget_bridge.dart').readAsStringSync();
    final updateBlock = bridgeSource.substring(
      bridgeSource.indexOf('static Future<bool?> Function(String) update'),
      bridgeSource.indexOf('/// Widget köprüsünü uygulamanın'),
    );
    expect(
      updateBlock,
      contains('androidName: name'),
      reason: 'provider tazelemesi androidName ile yapılmalı',
    );
    expect(
      RegExp(r'\bname:\s*name\b').hasMatch(updateBlock),
      isFalse,
      reason: '`name: name` paket öneki ekler ve sınıf çözümlemesini '
          'ClassNotFoundException ile bozar (home_widget 0.10.0)',
    );

    // 2) Kullanılan sınıf adları gerçek provider sınıfları olmalı.
    for (final className in ['DailyWidgetProvider', 'WeeklyWidgetProvider']) {
      expect(
        bridgeSource,
        contains("'$className'"),
        reason: '$className yayın listesinde yok',
      );
      final provider =
          File('android/app/src/main/kotlin/com/calorix/calorix/widget/'
                  '$className.kt')
              .readAsStringSync();
      expect(
        provider,
        contains('class $className'),
        reason: '$className.kt içinde sınıf tanımı bulunamadı',
      );
    }

    // 3) WidgetBridge.refreshAction ile Kotlin `ACTION_REFRESH` aynı olmalı
    //    ve AndroidManifest'te kayıtlı olmalı.
    expect(WidgetBridge.refreshAction, 'com.calorix.app.action.WIDGET_REFRESH');
    final daily =
        File('android/app/src/main/kotlin/com/calorix/calorix/widget/'
                'DailyWidgetProvider.kt')
            .readAsStringSync();
    expect(
      daily,
      contains('const val ACTION_REFRESH = "${WidgetBridge.refreshAction}"'),
      reason: 'ACTION_REFRESH sabiti WidgetBridge.refreshAction ile farklı',
    );
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(
      manifest,
      contains(WidgetBridge.refreshAction),
      reason: 'yayın aksiyonu manifest\'te kayıtlı değil — widget '
          'tazelenemez',
    );
  });

  test('buildStateSnapshot hiçbir anahtar için null yazmaz', () {
    // `WidgetData.kt` hiçbir anahtarın null olmadığını varsayıyor; Dart
    // tarafı nötr snapshot'ta da **tüm** anahtarları doldurmalı.
    final map = buildStateSnapshot(
      state: WidgetBridge.stateSignedOut,
      strings: testStrings,
      now: DateTime(2026, 9, 28),
      localeCode: 'tr',
    );
    expect(
      map.values.whereType<Object?>(),
      isNotEmpty,
      reason: 'nötr snapshot boş olmamalı',
    );
    // Sözleşmedeki anahtar sayısı tam olarak beklenen.
    expect(map.length, WidgetKeys.stateValues.length);
    // Ve anahtarların **kümesi** birebir aynı (eksik/fazla anahtar yok).
    expect(map.keys.toSet(), WidgetKeys.stateValues.toSet());
  });

  test('buildDailySnapshot de sözleşmedeki tüm anahtarları yazar', () {
    final map = buildDailySnapshot(
      daily: DailyData.empty,
      profile: null,
      settings: const WidgetSettings(),
      strings: testStrings,
      now: DateTime(2026, 9, 28),
      localeCode: 'tr',
    );
    // Günlük snapshot haftalık grafiği yazmaz; kalan anahtarlar tam olmalı.
    final weeklyKeys = {
      WidgetKeys.wValues,
      WidgetKeys.wLabels,
      WidgetKeys.wTodayIdx,
      WidgetKeys.wTarget,
      WidgetKeys.wAvg,
      WidgetKeys.wOnTarget,
      WidgetKeys.wShowAvg,
      WidgetKeys.wShowOnTarget,
    };
    expect(
      map.keys.toSet(),
      WidgetKeys.stateValues.toSet().difference(weeklyKeys),
    );
  });
}

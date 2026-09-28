/// Yedek içe aktarımının **durum dili**: plan, rapor ve hata sınıfları.
///
/// Bu dosya kasıtlı olarak `data_transfer_repository.dart`dan ayrıdır: hata
/// sınıfları arayüz katmanının (`lib/features/**`) yakalayacağı **sözleşmedir**
/// ve repository'nin gövdesinden bağımsız okunabilmelidir.
///
/// ## Neden sınıflı hatalar
///
/// `importData` eskiden `PostgrestException`/`TypeError`/`FormatException`
/// karışımı fırlatıyordu ve `transfer_dialogs.dart` her şeyi `catch (_)` ile
/// yutup "Bir hata oluştu" diyordu. Kullanıcı 6 ay önceki yedeğini geri
/// yüklerken yarısının gelip gelmediğini **öğrenemiyordu**.
///
/// Ayrım şu:
///
/// | Sınıf | Anlam | Yazma yapıldı mı? |
/// |---|---|---|
/// | [ImportFormatError] | Dosya CaloriX yedeği değil | hayır (ağ hiç çağrılmaz) |
/// | [ImportValidationError] | Yedek DB sözleşmesine uymuyor | **hayır** (ön-uçu) |
/// | [ImportWriteError] | Yazma sırasında hata | olabilir → [ImportWriteError.report] her zaman doludur |
library;

/// İçe aktarma sırasında işlenen tablolar — bağımlılık sırasında.
const List<String> kImportTables = <String>[
  'foods',
  'food_nutrition',
  'meal_entries',
  'water_entries',
  'weight_entries',
];

/// Bir satırın yazıma hazır hâli.
class PlannedRow {
  const PlannedRow(
    this.values, {
    this.backupId,
    this.backupName,
    this.dedupKey,
  });

  /// DB'ye gönderilecek kolon kümesi (sabit, tabloya göre).
  final Map<String, dynamic> values;

  /// Yedekteki `id` — hata raporlarında kullanıcıya gösterilir.
  final String? backupId;

  /// `foods` için gıda adı; `food_nutrition`/`meal_entries` için
  /// **başvurulan gıdanın adı** (yeni `food_id`'yi bulmak için).
  ///
  /// Gıda adları plan içinde benzersizdir (yedekteki tekrar eden adlar
  /// atlanır), bu yüzden ad üzerinden eşleme `id` üzerinden eşlemeden daha
  /// güvenlidir: Postgres `RETURNING` sırası değişse bile yanlış gıda
  /// `food_id`'si yazılmaz.
  final String? backupName;

  /// Varlık kontrolü anahtarı (`meal_entries`: `tarih|isim|tip`,
  /// `water_entries`: epoch mikrosaniye, `weight_entries`: tarih).
  final String? dedupKey;
}

/// Ön-uçu sonucu: **hiçbir istek atılmadan** hazırlanmış yazma planı.
class ImportPlan {
  ImportPlan();

  final List<PlannedRow> foods = [];
  final List<PlannedRow> nutrition = [];
  final List<PlannedRow> meals = [];
  final List<PlannedRow> water = [];
  final List<PlannedRow> weights = [];

  /// Yedekte tekrar eden (atlanan) besin `food_id`'leri.
  final Set<String> nutritionIds = <String>{};
  final Set<String> mealKeys = <String>{};
  final Set<String> waterKeys = <String>{};
  final Set<String> weightKeys = <String>{};

  /// Yedek gıda `id`si → gıda **adı**. `food_nutrition` ve `meal_entries`
  /// yedekteki eski `food_id` ile referans verir; import'ta bu id'ler yeni
  /// gıda id'sine çevrilir ve eşleme **ad** üzerinden yapılır.
  final Map<String, String> foodNameByBackupId = <String, String>{};

  /// Yedeğin `id`'siyle bilinen gıdanın adı (yoksa `null`).
  String? foodNameOf(String? backupId) =>
      backupId == null ? null : foodNameByBackupId[backupId];

  /// `in` sorguları için gereken değer listeleri (benzersiz, `inFilterChunks`
  /// ile dilimlenir).
  final Set<String> foodNames = <String>{};
  final Set<String> mealDates = <String>{};
  final Set<String> waterInstants = <String>{};
  final Set<String> weightDates = <String>{};

  /// DB'de zaten var olanlar (faz 2'de doldurulur) → bu satırlar yazılmaz.
  final Set<String> existingFoodNames = <String>{};
  final Set<String> existingMealKeys = <String>{};
  final Set<String> existingWaterKeys = <String>{};
  final Set<String> existingWeightDates = <String>{};

  /// DB'de zaten var olan gıda adı → `id`. Yedeğin `foods` listesi bu tabloyu
  /// doldurmuyorsa öğünler/besin satırları mevcut gıdaya bağlanır.
  ///
  /// `foods` üzerinde `UNIQUE(created_by, name)` **yoktur**
  /// (`full_setup.sql:70-80`): aynı adı taşıyan iki kullanıcı yemeği
  /// oluşabilir. Bu yüzden ilk eşleşme kazanır (web `useDataExport` ile aynı
  /// davranış) ve eşleme **kullanıcının kendi gıdaları** içinde yapılır
  /// (`.eq('created_by', userId)`).
  final Map<String, String> existingFoodIds = <String, String>{};

  /// Atlanan satır sayacı (tablo → adet).
  final Map<String, int> skipped = <String, int>{};

  /// Sessizce düzeltilen alan sayacı (`tablo.kolon` → adet).
  final Map<String, int> coerced = <String, int>{};

  /// Kullanıcıya gösterilebilecek tüm bulgular (atlanan + ölümcül).
  final List<ImportIssue> issues = <ImportIssue>[];

  /// Planlanan toplam satır (yazılacak olanlar).
  int get plannedRows =>
      foods.length + nutrition.length + meals.length + water.length + weights.length;

  @override
  String toString() => 'ImportPlan(foods: ${foods.length}, '
      'nutrition: ${nutrition.length}, meals: ${meals.length}, '
      'water: ${water.length}, weights: ${weights.length})';
}

/// Tek bir satır hakkında bulgu.
class ImportIssue {
  const ImportIssue({
    required this.table,
    required this.field,
    required this.message,
    this.rowId,
    this.isFatal = false,
  });

  /// Hangi tablo.
  final String table;

  /// Yedekteki satır `id`'si (yoksa `null`).
  final String? rowId;

  /// Hangi kolon.
  final String field;

  /// Kullanıcıya/operatöre gösterilebilecek açıklama.
  final String message;

  /// `true` ise içe aktarma **hiçbir şey yazmadan** durur.
  final bool isFatal;

  /// `tablo[ satir ] alan: mesaj` — **içerik sızdırmayan** tek satır.
  @override
  String toString() => '$table[${rowId ?? '?'}].$field: $message'
      '${isFatal ? ' (ölümcül)' : ''}';
}

/// İçe aktaramanın görünür sonucu.
class ImportReport {
  const ImportReport({
    required this.counts,
    this.skipped = const {},
    this.issues = const [],
    this.coerced = const {},
    this.failedStage,
    this.rolledBack,
    this.writtenTables = const {},
  });

  /// Eklenen kayıt sayıları (web `importedCount` parity). **Hata hâlinde de
  /// doludur**: `counts['meal_entries'] = 1200` yazıp 800. öğünde
  /// durduysak `1200` görünür, `{}` değil.
  final Map<String, int> counts;

  /// Atlanan satır sayacı (tablo → adet).
  final Map<String, int> skipped;

  /// Tüm bulgular.
  final List<ImportIssue> issues;

  /// Sessizce düzeltilen alanlar (`tablo.kolon` → adet) — "6 satırda
  /// geçersiz `meal_type`, 'snack' yapıldı" gibi.
  final Map<String, int> coerced;

  /// Hatanın olduğu adım (`foods`/`food_nutrition`/…); başarılıysa `null`.
  final String? failedStage;

  /// Telafi başarılı mı. `null` → hata olmadı.
  ///
  /// `false` ise **yazılan satırlar hâlâ duruyor** ve
  /// [writtenTables] hangi kayıtların eklendiğini tam olarak verir; bu
  /// durumda tekrar içe aktarmak dedup sayesinde güvenlidir.
  final bool? rolledBack;

  /// Telafi başarısız olduğunda yazılmış kalan satırların id'leri (tablo → id).
  final Map<String, List<String>> writtenTables;

  /// Toplam eklenen kayıt.
  int get totalAdded => counts.values.fold<int>(0, (a, b) => a + b);

  bool get isPartial =>
      failedStage != null || (rolledBack == false && writtenTables.isNotEmpty);

  @override
  String toString() => 'ImportReport(eklendi: $counts'
      '${skipped.isEmpty ? '' : ', atlandı: $skipped'}'
      '${coerced.isEmpty ? '' : ', düzeltildi: $coerced'}'
      '${failedStage == null ? '' : ', durdu: $failedStage, geri alındı: $rolledBack'})';
}

/// Dosya CaloriX yedeği değil (`version`/`exportedAt` yok, JSON bozuk).
///
/// `FormatException` **alt sınıfıdır**: `transfer_dialogs.dart`'ın mevcut
/// `on FormatException` kolu bunu zaten yakalıyor, yani arayüz değişmeden
/// "yalnızca CaloriX yedekleri desteklenir" mesajını gösterir.
class ImportFormatError extends FormatException {
  const ImportFormatError(super.message);
}

/// Ön-uçu doğrulaması yedeği reddetti — **hiçbir istek atılmadı**.
///
/// Bu, "önce doğrula, sonra yaz" kuralının somut hâlidir: `foods` dahil
/// **hiçbir tabloya yazılmadan** durulur. Kullanıcı yedeğini düzeltip
/// tekrar deneyebilir; yarım veri oluşmaz.
class ImportValidationError implements Exception {
  ImportValidationError(this.issues, {int? totalIssues})
      : assert(issues.isNotEmpty, 'en az bir ölümcül ihlal gerekir'),
        totalIssues = totalIssues ?? issues.length;

  /// Yalnızca **ölümcül** ihlaller.
  final List<ImportIssue> issues;

  /// Atlanan (ölümcül olmayan) bulgular dahil toplam.
  final int totalIssues;

  /// Kullanıcıya gösterilebilecek tek satırlık özet (dosya yolu/kolon içermez).
  String get summary {
    final first = issues.first;
    final more = issues.length - 1;
    final extra = more > 0 ? ' (+$more sorun daha)' : '';
    return 'Yedek doğrulanamadı: ${first.message}$extra';
  }

  @override
  String toString() => 'ImportValidationError: $summary';
}

/// Yazma sırasında hata — **rapor her zaman doludur**.
///
/// Taşıdığı [ImportReport] sayesinde "kaç kayıt yazıldı, hangi adımda
/// durdu, telafi edildi mi" sorularının üçü de yanıtlanır. Önceki sürümde
/// `counts` hiç dönmüyordu.
class ImportWriteError implements Exception {
  const ImportWriteError({
    required this.stage,
    required this.report,
    required this.cause,
    required this.stackTrace,
    this.code,
  });

  /// Hatanın olduğu adım (`'meal_entries'` gibi).
  final String stage;

  /// O ana kadar yazılanların dökümü + telafi durumu.
  final ImportReport report;

  /// Altta yatan hata (`PostgrestException` vb.).
  final Object cause;

  final StackTrace stackTrace;

  /// Postgres hata kodu (`23505`, `23514`, `PGRST204` …) — varsa.
  final String? code;

  /// Kullanıcıya gösterilebilecek tek satır. **Sunucu mesajını içermez:**
  /// PostgREST hata gövdesi tablo/kolon/kısıt adları taşıyabilir
  /// (`meal_entries_amount_g_ml_check`), bu yüzden yalnızca kendi metnimiz
  /// kullanılır (web `useDataExport.ts:333` ile aynı karar).
  String get summary {
    final rolled = report.rolledBack == true
        ? 'Eklenen kayıtlar geri alındı.'
        : 'Eklenen kayıtlar geri alınamadı.';
    return 'İçe aktarma "$stage" adımında durdu ($addedAdded). $rolled';
  }

  /// "şu kadar kayıt eklendi" ifadesi.
  String get addedAdded => '${report.totalAdded} kayıt eklenmişti';

  @override
  String toString() =>
      'ImportWriteError(stage: $stage, code: $code, report: $report, cause: $cause)';
}

/// Su kaydının çözümlenmiş zaman damgası.
class WaterInstant {
  const WaterInstant({
    required this.micros,
    required this.iso,
    required this.day,
  });

  /// UTC epoch mikrosaniye — dedup anahtarı.
  final int micros;

  /// DB'ye yazılacak ISO-8601 damga.
  final String iso;

  /// `entry_date` (`yyyy-MM-dd`).
  final String day;
}

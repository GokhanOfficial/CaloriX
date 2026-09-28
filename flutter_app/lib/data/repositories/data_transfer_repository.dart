import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/observability/app_logger.dart';
import '../supabase/supabase_client_provider.dart';
import 'auth_repository.dart';
import 'data_transfer_import.dart';

export 'data_transfer_import.dart';

/// Web `useDataExport.ts` karşılığı — tüm kullanıcı verilerini JSON olarak
/// dışa aktarır ve yedekten içe aktarır (yalnızca eklemeli, dedup'lı).
///
/// DB kapalıyken bu fonksiyonlar canlı veriye dokunmaz; birim mantığı
/// (dedup, şema) web ile birebir aynıdır.
class DataTransferRepository {
  DataTransferRepository(this._client);

  final SupabaseClient _client;

  /// `inFilter` değerleri **sorgu dizesine** gömülür (`?col=in.("a","b")`).
  ///
  /// PostgREST'in önerilen pratik URL tavanı ~8 KB'dir; bunu aşan bir
  /// `in` listesi **414 URI Too Long** ile reddedilir (bazı reverse proxy'lerde
  /// 400/431). Ters proxy olmayan `supabase.co` uçlarındaki `max-rows`/güneven
  /// katmanlarında ise bağlantı "Header or Cookie too large" olarak kopar.
  ///
  /// Aşılması matematiksel olarak kaçınk değil: `_cleanFilterArray` (postgrest
  /// 2.9.1, `postgrest_builder.dart:635`) **dize değerlerini çift tırnakla
  /// sarar** → 36 haneli bir UUID + 2 tırnak + virgül = 39 bayt. 8 KB'de
  /// 210 kayıt; 5000 `entry_time` dedup'i 195 KB'lık bir tek sorgu demek.
  ///
  /// 100 güvenli: en kötü kayıt ~60 bayt → ~6 KB. `uuidGenerateV4` 2000'lik
  /// yedekte URL sınırının **%48'i**; 5000'lik yedekte tek parça zaten
  /// 414 alırdı. Daha küçük dilimler yalnızca daha çok istek demek.
  static const int inFilterChunkSize = 100;

  /// İçe aktarımda tek HTTP isteğinde gönderilecek en fazla satır.
  ///
  /// PostgREST çok satırlı `POST`'u **tek SQL deyimi** olarak gönderir, yani
  /// bir dilim ya tamamen yazılır ya hiç — kısmi yazım mümkün değildir.
  /// Sınır iki kısıtla belirlenir:
  ///
  ///  * **Postgres parametre tavanı 65535.** En geniş tablo `meal_entries`
  ///    (14 kolon) → 500 satır = 7000 parametre (%11).
  ///  * **Gövde boyutu.** 500 öğün ≈ 200 KB; mobil bağlantıda güvenli, ama
  ///    daha büyük dilimler uygulamanın bellek bütçesini gereksiz zorlar.
  ///
  /// Ölçüm (bkz. rapor): 2000 öğün + 2000 su + 400 kilo + 40 gıda yedeği
  /// satır satır yazıldığında **4506 istek** üretiyordu; toplu yazımda
  /// **62 istek** (~72× azalma), `importBatchSize = 1`'deki 4506 isteğe göre
  /// hata toleransı da yine tek deyimlik bloklarla korunur.
  static const int importBatchSize = 500;

  /// `meal_entries.amount_g_ml` CHECK üst sınırı
  /// (`20260927120000_security_hardening_round1.sql:389`).
  static const double maxAmountGMl = 10000;

  /// `water_entries.amount_ml` CHECK üst sınırı (aynı migration :395).
  static const int maxAmountMl = 10000;

  /// `weight_entries.weight_kg` CHECK üst sınırı (aynı migration :401).
  static const double maxWeightKg = 1000;

  /// `meal_type` DB değerleri — PostgreSQL `meal_type` ENUM ve DB CHECK
  /// kısıtı (migration `20260111041204_...sql:11`, `full_setup.sql:23`).
  ///
  /// Yedek içe aktarımında geçersiz bir `meal_type` insert'i CHECK ihlaliyle
  /// 400 döndürür ve **tüm içe aktarma** orada durur; içe aktarma planı bu
  /// listeyi kullanır. `MealType` enum'u ile küme olarak birebir eşit
  /// olmalıdır (`import_sanitize_test.dart` sözleşme testiyle denetlenir).
  static const Set<String> mealTypeDbValues = {
    'breakfast',
    'lunch',
    'dinner',
    'snack',
  };

  // ------------------------------------------------------------------
  // EXPORT — web `exportData` parity: 8 paralel sorgu
  // ------------------------------------------------------------------

  /// Tüm kullanıcı verisini içeren JSON string üretir.
  Future<String> exportData(String userId) async {
    final profileFuture =
        _client.from('profiles').select().eq('id', userId).maybeSingle();
    final mealsFuture = _client
        .from('meal_entries')
        .select()
        .eq('user_id', userId)
        .isFilter('deleted_at', null);
    final waterFuture = _client
        .from('water_entries')
        .select()
        .eq('user_id', userId)
        .isFilter('deleted_at', null);
    final weightsFuture = _client
        .from('weight_entries')
        .select()
        .eq('user_id', userId)
        .isFilter('deleted_at', null);
    final foodsFuture =
        _client.from('foods').select().eq('created_by', userId);
    final favoritesFuture =
        _client.from('favorite_foods').select().eq('user_id', userId);
    final recentsFuture =
        _client.from('recent_foods').select().eq('user_id', userId);
    final notifFuture = _client
        .from('notification_preferences')
        .select()
        .eq('user_id', userId);

    final results = await Future.wait<dynamic>([
      profileFuture,
      mealsFuture,
      waterFuture,
      weightsFuture,
      foodsFuture,
      favoritesFuture,
      recentsFuture,
      notifFuture,
    ]);

    final profile = results[0];
    final meals = results[1] as List;
    final water = results[2] as List;
    final weights = results[3] as List;
    final foods = results[4] as List;
    final favorites = results[5] as List;
    final recents = results[6] as List;
    final notifs = results[7] as List;

    // Kullanıcıya ait yemeklerin besin satırları (food_nutrition).
    final foodIds = <String>[
      for (final f in foods)
        if ((f as Map)['id'] != null) f['id'].toString(),
    ];
    final nutrition = <dynamic>[
      for (final chunk in inFilterChunks(foodIds))
        ...await _client
            .from('food_nutrition')
            .select()
            .inFilter('food_id', chunk) as List,
    ];

    final payload = <String, dynamic>{
      'version': AppConstants.appVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'profile': profile,
      'meal_entries': meals,
      'water_entries': water,
      'weight_entries': weights,
      'foods': foods,
      'food_nutrition': nutrition,
      'favorite_foods': favorites,
      'recent_foods': recents,
      'notification_preferences': notifs,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  // ------------------------------------------------------------------
  // IMPORT — "önce doğrula, sonra yaz" üç fazlı akış
  // ------------------------------------------------------------------

  /// Yedek JSON'unu eklemeli olarak içe aktarır ve **dokunulan kayıt
  /// sayılarını** döndürür (web `importData` parity, sadeleştirilmiş sözleşme).
  ///
  /// Hata hâlinde eklenen kayıt sayısı **istisnada** taşınır
  /// ([ImportWriteError.report]) — kısmi import'un sayısı kaybolmaz.
  /// Ayrıntılı rapor isteyen çağıran [importBackup]'ı kullanmalıdır.
  Future<Map<String, int>> importData(String userId, String jsonString) async =>
      (await importBackup(userId, jsonString)).counts;

  /// Yedek içe aktarımı — **doğrula → yaz → (hata olursa) telafi et**.
  ///
  /// ## Neden bu akış
  ///
  /// PostgREST'te çok istekli bir yazma dizisi **atomik değildir**: her
  /// `POST` kendi transaction'ıdır. Önceki sürümde `importData` satır satır
  /// yazıyordu; 500. öğünde bir CHECK ihlali (`23514`) oluştuğunda 2000 öğünlük
  /// bir yedekte `foods` + `food_nutrition` + 500 öğün **yazılmış** kalıyor,
  /// `counts` hiç dönmüyordu ve `transfer_dialogs.dart` `catch (_)` ile
  /// yutuyordu. Kullanıcı "hata" görüyor, hangi öğünlerin geldiğini
  /// bilmiyordu — bu bir **veri bozulması** senaryosudur.
  ///
  /// ## Üç faz
  ///
  /// 1. **Ön-uçu (ağ yok).** Yedek ayrıştırılır ve tüm satırlar DB sözleşmesine
  ///    göre denetlenir. **Tek bir ölümcül ihlalde hiçbir istek atılmaz**
  ///    ([ImportValidationError]) — "önce doğrula, sonra yaz".
  /// 2. **Varlık kontrolü (yalnız GET).** Dedup anahtarları dilimli `in`
  ///    sorgularıyla okunur; yazma yine yapılmaz.
  /// 3. **Yazma (toplu + telafili).** Tablolar bağımlılık sırasıyla yazılır.
  ///    Hata olursa o turda yazılan satırların `id`'leri toplanır ve
  ///    **fiziksel olarak silinir**; ardından ne yazıldığını tam olarak
  ///    söyleyen bir [ImportReport] ile [ImportWriteError] fırlatılır.
  ///    Telafi de başarısız olursa `rolledBack = false` ile rapor **yazılan
  ///    satırları tek tek sayar** — yani her durumda görünür bir sonuç üretilir.
  ///
  /// ## Doğrulama sözleşmesi (testlerle sabitli)
  ///
  /// | Durum | Sonuç |
  /// |---|---|
  /// | Dosya CaloriX yedeği değil | [ImportFormatError] — ağ hiç çağrılmaz |
  /// | Satır zorunlu kolonlara DB'nin **kabul etmeyeceği** değer yazıyor (aralık dışı miktar/kilo, sayı olmayan zorunlu sayı) | [ImportValidationError] + tüm ihlaller listesi — **hiçbir yazma yok** |
  /// | Satır kimliksiz/gereksiz (isimsiz gıda, anahtarsız öğün, `deleted_at` dolu, yinelenen dedup anahtarı) | atlanır, [ImportReport.skipped] + [ImportIssue] |
  /// | Alan güvenli varsayılana çekilebiliyor (geçersiz `meal_type`→snack, `source`→manual, `amount_ml` 250.4→250) | yazılır, [ImportReport.coerced] artar |
  /// | Yazma hatası | telafi + [ImportWriteError] (rapor her zaman dolu) |
  Future<ImportReport> importBackup(
    String userId,
    String jsonString,
  ) async {
    // FAZ 1 — ayrıştırma + ön-uçu doğrulama. **Ağ çağrısı yoktur.**
    final data = _decodeBackup(jsonString);
    final plan = buildImportPlan(userId, data);

    // FAZ 2 — varlık kontrolü (yalnızca GET).
    await _loadExistingKeys(userId, plan);

    // FAZ 3 — yazma (toplu, telafili).
    return _apply(userId, plan);
  }

  /// Yedeği ayrıştırır ve biçim sözleşmesini doğrular.
  ///
  /// [ImportFormatError], `transfer_dialogs.dart`'ın mevcut
  /// `on FormatException` koluna düşer (FormatException alt sınıfı) → geçersiz
  /// dosyada arayüz değişmeden doğru mesajı gösterir.
  static Map<String, dynamic> _decodeBackup(String jsonString) {
    Object? decoded;
    try {
      decoded = jsonDecode(jsonString);
    } on FormatException catch (e, s) {
      AppLog.w('Yedek dosyası JSON değil', e, s);
      throw ImportFormatError('Geçersiz CaloriX yedek dosyası (JSON okunamadı).');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] == null ||
        decoded['exportedAt'] == null) {
      throw const ImportFormatError('Geçersiz CaloriX yedek dosyası');
    }
    return decoded;
  }

  /// Yedek satırlarını DB sözleşmesine göre **yazmaya hazır** hâle getirir.
  ///
  /// **Saf fonksiyon** (ağ yok, yan etki yok) — bu sayede "doğrulama hatasında
  /// hiçbir yazma olmaması" davranışı testte kanıtlanabilir: fonksiyon
  /// istisna fırlattığında istemciye hiç dokunulmamıştır.
  ///
  /// [userId] yazılacak `user_id`/`created_by` değeridir; yedekteki başka bir
  /// kullanıcıya ait `user_id` **yok sayılır** (başka birinin yedeği
  /// kullanıcıya verilse bile kayıtlar doğru sahiplikle yazılır).
  @visibleForTesting
  static ImportPlan buildImportPlan(String userId, Map<String, dynamic> data) {
    final issues = <ImportIssue>[];
    final coerced = <String, int>{};

    // 1) Gıdalar — dedup: `name` + `created_by`.
    final foods = _rowsOf(data['foods']);
    final plan = ImportPlan();
    final seenFoodNames = <String>{};
    for (final food in foods) {
      final name = food['name'];
      if (name is! String || name.trim().isEmpty) {
        _skip(plan, 'foods', issues, 'name', 'Gıdanın adı boş', food['id']);
        continue;
      }
      final key = name.trim();
      if (!seenFoodNames.add(key)) {
        _skip(plan, 'foods', issues, 'name',
            'Yedekte aynı adı taşıyan ikinci gıda (tekrar sayıldı)', food['id']);
        continue;
      }
      final oldId = food['id']?.toString();
      if (oldId == null || oldId.isEmpty) {
        _skip(plan, 'foods', issues, 'id',
            'Gıdanın kimliği yok — öğünlerle eşleştirilemez', null);
        continue;
      }
      final row = _foodRow(food, userId, key, issues, coerced);
      plan.foodNames.add(key);
      plan.foodNameByBackupId[oldId] = key;
      plan.foods.add(PlannedRow(row, backupId: oldId, backupName: key));
    }

    // 2) food_nutrition — `food_id` içe aktarımda **yeni** gıda id'sidir.
    //
    // `food_nutrition.food_id` UNIQUE (`full_setup.sql:121`): aynı gıdaya
    // ikinci besin satırı eklemek `23505 duplicate key` ile **tüm import'u**
    // düşürürdü. Yedekte aynı `food_id` için birden çok satır varsa ilki
    // kazanır (deterministik), geri kalanı atlanır.
    final nutrition = _rowsOf(data['food_nutrition']);
    for (final n in nutrition) {
      final oldFoodId = n['food_id']?.toString();
      if (oldFoodId == null || oldFoodId.isEmpty) {
        _skip(plan, 'food_nutrition', issues, 'food_id',
            'Besin satırının gıda bağlantısı yok', null);
        continue;
      }
      if (!plan.foods.any((f) => f.backupId == oldFoodId)) {
        // Yedeğin `foods` listesinde karşılığı yok (elle düzenlenmiş yedek).
        _skip(plan, 'food_nutrition', issues, 'food_id',
            'Besin satırının gıdası yedekte yok', oldFoodId);
        continue;
      }
      if (plan.nutritionIds.add(oldFoodId)) {
        plan.nutrition.add(PlannedRow(
          _nutritionRow(n, issues, coerced),
          backupId: oldFoodId,
        ));
      } else {
        _skip(plan, 'food_nutrition', issues, 'food_id',
            'Aynı gıda için ikinci besin satırı (UNIQUE food_id)', oldFoodId);
      }
    }

    // 3) meal_entries — dedup: `entry_date` + `custom_name` + `meal_type`.
    //
    // `meal_entries` üzerinde bu kombinasyona UNIQUE constraint yoktur, bu
    // yüzden `maybeSingle()` **birden fazla eşleşmede istisna fırlatır** ve
    // içe aktarma tamamen çöker (aynı gün/öğünde iki ayrı "Tavuk" kaydı
    // yedeklenmiş olan kullanıcılar için 100% olası). Varlık kontrolü
    // `in`-filtreli sorgularla yapılır (tarihler dilimli — bkz.
    // [inFilterChunkSize]).
    // Yumuşak silinmiş satırlar **varlık kontrolüne de** girmemeli: aksi
    // halde DB'deki canlı ama farklı kayıtla aynı anahtarı taşıyan bir
    // silinmiş satın varlığı, canlı satırın yeniden eklenmesini engeller.
    final meals = _liveRowsOf(data['meal_entries']);
    for (final m in meals) {
      // Tarih **çözümlenemiyorsa** ölümcüldür: öğünün nereye yazılacağı
      // bilinmiyor. Sessizce atlamak kullanıcının yedeğinden bir gün
      // kaybettirir ve bunu bildirecek bir yer de yoktur (eski sürümde
      // ham dize gönderilip DB 400 veriyordu → tüm import düşüyordu).
      final day = _dateString(m['entry_date']);
      if (day == null) {
        issues.add(ImportIssue(
          table: 'meal_entries',
          rowId: m['id']?.toString(),
          field: 'entry_date',
          message: 'Öğünün tarihi okunamadı (beklenen: yyyy-MM-dd)',
          isFatal: true,
        ));
        continue;
      }
      // `meal_type` enum dışıysa DB varsayılanına çekilir, ölümcül değildir.
      final normalized = <String, dynamic>{...m, 'entry_date': day};
      final key = _mealKey(normalized);
      if (key == null) {
        _skip(plan, 'meal_entries', issues, 'meal_type',
            'Öğünün tipi eksik — nereye yazılacağı bilinmiyor', m['id']);
        continue;
      }
      if (!plan.mealKeys.add(key)) {
        _skip(plan, 'meal_entries', issues, 'entry_date',
            'Yedekte aynı gün/öğün/yemek için ikinci kayıt (tekrar sayıldı)',
            m['id']);
        continue;
      }
      plan.mealDates.add(day);
      // Öğün yedekteki gıdayı `food_id` ile referanslıyor; import'ta bu id
      // **yeni** gıda id'sine çevrilir, karşılık yoksa `null` (manuel girdi).
      plan.meals.add(PlannedRow(
        _mealRow(m, userId, issues, coerced),
        backupId: m['id']?.toString(),
        backupName: plan.foodNameOf(m['food_id']?.toString()),
        dedupKey: key,
      ));
    }

    // 4) water_entries — dedup: `entry_time`.
    // `entry_time` timestamptz NOT NULL UNIQUE değil → `maybeSingle()` iki
    // kayıtta patlar. Aynı kombinasyon anahtarı ile toplu kontrol yapılır.
    final waters = _liveRowsOf(data['water_entries']);
    for (final w in waters) {
      // `entry_time NOT NULL` ve dedup anahtarı bu damga → zamanı
      // çözümlenemeyen kayıt **ölümcüldür** (sessizce atlanırsa kullanıcının
      // günlük su toplamı eksik kalır, bildirim de gelmez).
      final when = _waterInstant(w, issues, coerced);
      if (when == null) {
        issues.add(ImportIssue(
          table: 'water_entries',
          rowId: w['id']?.toString(),
          field: 'entry_time',
          message: 'Su kaydının zamanı okunamadı '
              '(beklenen ISO-8601 damga veya entry_date)',
          isFatal: true,
        ));
        continue;
      }
      final key = when.micros.toString();
      plan.waterInstants.add(when.iso);
      if (!plan.waterKeys.add(key)) {
        _skip(plan, 'water_entries', issues, 'entry_time',
            'Yedekte aynı anda ikinci su kaydı (tekrar sayıldı)', w['id']);
        continue;
      }
      final row = _waterRow(w, userId, when, issues, coerced);
      plan.water.add(PlannedRow(row, backupId: w['id']?.toString(), dedupKey: key));
    }

    // 5) weight_entries — dedup: `entry_date`.
    // Aynı gün iki kilo kaydı olabilir (UNIQUE constraint yok) →
    // `maybeSingle()` yerine toplu `in` kontrolü.
    final weights = _liveRowsOf(data['weight_entries']);
    for (final w in weights) {
      // Kilo kaydının günü **ölümcüldür**: `entry_date DATE NOT NULL` ve
      // dedup anahtarı da bu gün. Tarihi okunamayan bir kilo kaydı sessizce
      // atlanırsa kullanıcının kilo trendi eksik kalır ve bunu öğrenemez
      // (eski sürüm ham dizeyi gönderip DB 400 veriyordu → tüm import
      // düşüyordu, yine de kullanıcı "hangi kilo kaydı bozukdu?" öğrenemiyordu).
      final day = _dateString(w['entry_date']);
      if (day == null) {
        issues.add(ImportIssue(
          table: 'weight_entries',
          rowId: w['id']?.toString(),
          field: 'entry_date',
          message: 'Kilo kaydının tarihi okunamadı (beklenen: yyyy-MM-dd)',
          isFatal: true,
        ));
        continue;
      }
      plan.weightDates.add(day);
      if (!plan.weightKeys.add(day)) {
        _skip(plan, 'weight_entries', issues, 'entry_date',
            'Yedekte aynı gün için ikinci kilo kaydı (tekrar sayıldı)', w['id']);
        continue;
      }
      plan.weights.add(PlannedRow(
        _weightRow(w, userId, day, issues, coerced),
        backupId: w['id']?.toString(),
        dedupKey: day,
      ));
    }

    // 6) favorite_foods / recent_foods — **gıda adı üzerinden** eşlenir.
    //
    // ## Neden bu tablo eski sürümde yoktu
    //
    // `exportData` her ikisini de dışa aktarıyordu (`:109/:111/:159/:160`)
    // ama `importData` hiç okumuyordu: kullanıcı yedeği geri yüklediğinde
    // favorileri **sessizce kayboluyordu** ve "beklediği şey geri gelmiyordu".
    //
    // ## `food_id` eşleşmezse ne olmalı?
    //
    // `favorite_foods.food_id` **NOT NULL** (`full_setup.sql:188`) — öğünlerdeki
    // gibi `null` bırakılamaz. Üç seçenek vardı:
    //
    //  * **Ölümcül** → tek eski-kopmuş bir favori, kullanıcının
    //    günlüklerinin tamamını geri yükleyememesine yol açar. Favoriler
    //    geri getirmeye **çalışan** bir özelliktir; onu şart koşmak tersi
    //    etkiyi doğurur (P0'a yükselirdi).
    //  * **Sessizce atlamak** → kullanıcı favorilerinin bir kısmı geri
    //    geldiğini sanır. A2r4'ün "sessiz veri kaybı" yasağına aykırı.
    //  * **Atla + raporla** (seçilen) → `ImportReport.skipped` +
    //    `ImportIssue` ile kullanıcı bilgilendirilir, geri kalan yedek
    //    eksiksiz geri gelir. Öğünlerle aynı davranış (`food_nutrition`'ın
    //    gıdası yedekte yoksa atlanır, `:308`).
    //
    // Yedekte `foods` listesinde karşılığı olmayan bir `food_id` normal
    // değildir: `exportData` favorileri **kendi gıdalarıyla** birlikte
    // alır (`foods`: `.eq('created_by', userId)`) ve bu tablo FK'si
    // `foods(id)`'dir. Yani eşleşmeme yalnızca **elle düzenlenmiş** yedekte
    // ya da gıdanın `foods`'tan silinmiş olmasında olur — ikisi de "bu
    // favori geri getirilemez" demektir, ölümcül hata değil.
    for (final entry in <({String table, List<PlannedRow> into})>[
      (table: 'favorite_foods', into: plan.favorites),
      (table: 'recent_foods', into: plan.recents),
    ]) {
      final seen = entry.table == 'favorite_foods'
          ? plan.favoriteNames
          : plan.recentNames;
      for (final f in _rowsOf(data[entry.table])) {
        final oldFoodId = f['food_id']?.toString();
        if (oldFoodId == null || oldFoodId.isEmpty) {
          _skip(plan, entry.table, issues, 'food_id',
              'Favori/son kullanılan kaydının gıda bağlantısı yok', f['id']);
          continue;
        }
        // Yedeğin `foods` listesinde karşılığı yok (elle düzenlenmiş
        // yedek ya da gıda silinmiş) → geri getirilemez, atlanır.
        final name = plan.foodNameOf(oldFoodId);
        if (name == null) {
          _skip(plan, entry.table, issues, 'food_id',
              'Kaydın gıdası yedekte yok — favori geri getirilemedi',
              oldFoodId);
          continue;
        }
        // Aynı gıda ikinci kayıt → `UNIQUE(user_id, food_id)` ihlali
        // (23505) ile **tüm import'u** düşürürdü.
        if (!seen.add(name)) {
          _skip(plan, entry.table, issues, 'food_id',
              'Yedekte aynı gıda için ikinci kayıt (UNIQUE user_id+food_id)',
              oldFoodId);
          continue;
        }
        entry.into.add(PlannedRow(
          _foodLinkRow(f, userId, entry.table, issues, coerced),
          backupId: f['id']?.toString(),
          backupName: name,
          dedupKey: name,
        ));
      }
    }

    // 7) notification_preferences — `UNIQUE(user_id, notification_type)`.
    //
    // Bu tablo da `exportData`'da var (`:113/:161`) ama import yoktu:
    // geri yüklemede kullanıcının bildirim tercihleri sıfırlanıyordu.
    // DB CHECK'leri (`notification_preferences_type_allowlist`,
    // `notification_preferences_hours_range` —
    // `20260927120000_security_hardening_round1.sql:411-423`) ihlal
    // eden bir satır 400 döndürür ve **tüm import'u** düşürürdü; bu
    // yüzden geçersiz alanlar DB varsayılanına çekilir ve **sayeç** artar.
    for (final n in _rowsOf(data['notification_preferences'])) {
      final type = _str(n['notification_type']);
      if (type == null) {
        _skip(plan, 'notification_preferences', issues, 'notification_type',
            'Bildirim tercihinin türü boş', n['id']);
        continue;
      }
      if (!_notificationTypeDbValues.contains(type)) {
        _skip(plan, 'notification_preferences', issues, 'notification_type',
            'DB CHECK dışı bildirim türü ("$type")', n['id']);
        continue;
      }
      if (!plan.notificationTypes.add(type)) {
        _skip(plan, 'notification_preferences', issues, 'notification_type',
            'Yedekte aynı tür için ikinci tercih (UNIQUE user_id+type)',
            n['id']);
        continue;
      }
      plan.notificationTypeList.add(type);
      plan.notificationPrefs.add(PlannedRow(
        _notificationPrefRow(n, userId, type, issues, coerced),
        backupId: n['id']?.toString(),
        dedupKey: type,
      ));
    }

    // Ölümcül ihlal varsa **hiçbir yazma yapılmadan** dur.
    final fatal = issues.where((i) => i.isFatal).toList(growable: false);
    if (fatal.isNotEmpty) {
      throw ImportValidationError(fatal, totalIssues: issues.length);
    }
    plan.coerced.addAll(coerced);
    plan.issues.addAll(issues);
    return plan;
  }

  // ------------------------------------------------------------------
  // FAZ 2 — varlık kontrolü (yalnız GET)
  // ------------------------------------------------------------------

  /// DB'de zaten var olan dedup anahtarlarını plana işaretler.
  ///
  /// Tüm sorgular `in` listesi dilimlenir (bkz. [inFilterChunkSize]): yedek
  /// binlerce günü kapsadığında tek `in` listesi ~8 KB URL tavanını aşar ve
  /// sorgu 414/431 ile düşer (içe aktarma 2000+ kayıtta çalışmıyordu).
  Future<void> _loadExistingKeys(String userId, ImportPlan plan) async {
    for (final chunk in inFilterChunks(plan.foodNames.toList())) {
      final rows = await _client
          .from('foods')
          .select('id, name')
          .eq('created_by', userId)
          .inFilter('name', chunk);
      for (final row in rows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final name = map['name'] as String?;
        final id = map['id']?.toString();
        if (name != null && name.trim().isNotEmpty) {
          final key = name.trim();
          plan.existingFoodNames.add(key);
          // Aynı adlı iki kullanıcı yemeği olabilir (`foods` üzerinde UNIQUE
          // yok) → ilk eşleşme kazanır.
          if (id != null) plan.existingFoodIds.putIfAbsent(key, () => id);
        }
      }
    }

    for (final chunk in inFilterChunks(plan.mealDates.toList())) {
      final rows = await _client
          .from('meal_entries')
          .select('entry_date, custom_name, meal_type')
          .eq('user_id', userId)
          .inFilter('entry_date', chunk);
      for (final row in rows as List) {
        final k = _mealKey(Map<String, dynamic>.from(row as Map));
        if (k != null) plan.existingMealKeys.add(k);
      }
    }

    // `entry_time` karşılaştırması **dize değil, epoch mikrosaniye** üzerinden
    // yapılır: Postgres `timestamptz` çıktısı ile yedeğin damga biçimi
    // farklı olabilir (`+00:00` ↔ `Z`), dize karşılaştırması dedup'ı kırar
    // ve aynı su kaydı iki kez eklenirdi.
    for (final chunk in inFilterChunks(plan.waterInstants.toList())) {
      final rows = await _client
          .from('water_entries')
          .select('entry_time')
          .eq('user_id', userId)
          .inFilter('entry_time', chunk);
      for (final row in rows as List) {
        final t = _epochMicros((row as Map)['entry_time']);
        if (t != null) plan.existingWaterKeys.add(t.toString());
      }
    }

    for (final chunk in inFilterChunks(plan.weightDates.toList())) {
      final rows = await _client
          .from('weight_entries')
          .select('entry_date')
          .eq('user_id', userId)
          .inFilter('entry_date', chunk);
      for (final row in rows as List) {
        final d = _dateString((row as Map)['entry_date']);
        if (d != null) plan.existingWeightDates.add(d);
      }
    }

    // favorite_foods / recent_foods — varlık kontrolü **ad üzerinden**.
    //
    // Dedup anahtarı `UNIQUE(user_id, food_id)`'dir ama `food_id` import'ta
    // **yeni** bir UUID alır; yedekteki eski UUID DB'de yoktur. Bu yüzden
    // iki tablo birlikte okunur (`foods(name)` embed'li) ve eşleşme
    // **ad** üzerinden yapılır — öğün/besin satırlarıyla aynı desen.
    //
    // Kullanıcının **kendi gıdaları** içinde süzülür: `foods` RLS'i herkese
    // açık (`USING (true)`, `full_setup.sql:284`), yani `created_by` filtresi
    // olmadan **başkasının gıdası** da favorilere yazılabilirdi.
    final wantedNames = {...plan.favoriteNames, ...plan.recentNames};
    final favoriteNames = <String>{};
    final recentNames = <String>{};
    for (final chunk in inFilterChunks(wantedNames.toList())) {
      for (final entry in <({String table, Set<String> into})>[
        (table: 'favorite_foods', into: favoriteNames),
        (table: 'recent_foods', into: recentNames),
      ]) {
        final rows = await _client
            .from(entry.table)
            .select('foods!inner(name)')
            .eq('user_id', userId)
            .inFilter('foods.name', chunk);
        for (final row in rows as List) {
          final joined = (row as Map)['foods'];
          final name = joined is Map ? joined['name'] : null;
          if (name is String && name.trim().isNotEmpty) {
            entry.into.add(name.trim());
          }
        }
      }
    }
    plan.existingFavoriteNames.addAll(favoriteNames);
    plan.existingRecentNames.addAll(recentNames);

    for (final chunk in inFilterChunks(plan.notificationTypeList.toList())) {
      final rows = await _client
          .from('notification_preferences')
          .select('notification_type')
          .eq('user_id', userId)
          .inFilter('notification_type', chunk);
      for (final row in rows as List) {
        final t = (row as Map)['notification_type'];
        if (t is String) plan.existingNotificationTypes.add(t);
      }
    }
  }

  // ------------------------------------------------------------------
  // FAZ 3 — yazma (toplu + telafili)
  // ------------------------------------------------------------------

  /// Planı uygular. Hata olursa o turda yazılanları geri alır ve
  /// [ImportWriteError] fırlatır.
  Future<ImportReport> _apply(String userId, ImportPlan plan) async {
    final counts = <String, int>{for (final t in importTables) t: 0};
    // Telafi için yazılan satır id'leri (tablo → id'ler). Bağımlılık
    // sırasının **tersinde** silinir; `foods` silinince `food_nutrition`
    // `ON DELETE CASCADE` ile zaten gider.
    final written = <String, List<String>>{};
    var stage = 'foods';
    try {
      // 1) foods + food_nutrition (besin satırları yeni gıda id'sine bağlı).
      //
      // `plan.existingFoodNames` içindeki gıdalar **yeniden yazılmaz**;
      // öğünler/besin satırları onların **mevcut** id'sine bağlanır (ad
      // bazlı dedup — `foods` üzerinde UNIQUE yok, ilk eşleşme kazanır).
      stage = 'foods';
      final foodIdByName = <String, String>{...plan.existingFoodIds};
      final toInsert = [
        for (final r in plan.foods)
          if (!plan.existingFoodNames.contains(r.backupName)) r,
      ];
      if (toInsert.isNotEmpty) {
        final inserted =
            await _insertBatched('foods', [for (final r in toInsert) r.values]);
        foodIdByName.addAll(_idMapByBackupName(toInsert, inserted));
        counts['foods'] = inserted.length;
        written['foods'] = inserted.map((r) => r['id'].toString()).toList();
      }

      stage = 'food_nutrition';
      // Besin satırı, gıdası **zaten DB'de**yse yazılmaz: `food_nutrition`
      // `UNIQUE(food_id)` (`full_setup.sql:121`) ve mevcut gıdanın besin
      // satırı büyük olasılıkla zaten var → `23505 duplicate key` ile tüm
      // import'u düşürürdü. Yeni eklenen gıdaların satırları yazılır.
      final nutritionRows = [
        for (final r in plan.nutrition)
          if (!plan.existingFoodNames.contains(plan.foodNameOf(r.backupId)))
            {
              ...r.values,
              'food_id': foodIdByName[plan.foodNameOf(r.backupId)],
            },
      ];
      if (nutritionRows.isNotEmpty) {
        final unresolved =
            nutritionRows.where((r) => r['food_id'] == null).length;
        if (unresolved > 0) {
          throw StateError(
              'Besin satırının gıdası içe aktarımda eşleştirilemedi '
              '($unresolved satır)');
        }
        await _insertBatched('food_nutrition', nutritionRows);
        counts['food_nutrition'] = nutritionRows.length;
      }

      // 2) Günlük kayıtlar.
      stage = 'meal_entries';
      final meals = [
        for (final r in plan.meals)
          if (!plan.existingMealKeys.contains(r.dedupKey))
            {
              ...r.values,
              // Yedekteki `food_id` eski UUID'dir; yoksa manuel girdidir.
              'food_id': r.backupName == null ? null : foodIdByName[r.backupName],
            },
      ];
      final newMeals = await _insertBatched('meal_entries', meals);
      counts['meal_entries'] = newMeals.length;
      if (newMeals.isNotEmpty) {
        written['meal_entries'] = newMeals.map((r) => r['id'].toString()).toList();
      }

      stage = 'water_entries';
      final waters = [
        for (final r in plan.water)
          if (!plan.existingWaterKeys.contains(r.dedupKey)) r.values,
      ];
      final newWaters = await _insertBatched('water_entries', waters);
      counts['water_entries'] = newWaters.length;
      if (newWaters.isNotEmpty) {
        written['water_entries'] = newWaters.map((r) => r['id'].toString()).toList();
      }

      stage = 'weight_entries';
      final weights = [
        for (final r in plan.weights)
          if (!plan.existingWeightDates.contains(r.dedupKey)) r.values,
      ];
      final newWeights = await _insertBatched('weight_entries', weights);
      counts['weight_entries'] = newWeights.length;
      if (newWeights.isNotEmpty) {
        written['weight_entries'] = newWeights.map((r) => r['id'].toString()).toList();
      }

      // 3) favorite_foods / recent_foods.
      //
      // `food_id` **NOT NULL FK** — `null` bırakılamaz; eşleşmeyen kayıt
      // zaten `buildImportPlan`'da atlanmış ve raporlanmıştır. Buraya
      // sızan eşleşmesiz satır (gıda `RETURNING` ile eşleşmedi) sessizce
      // yazılmaz: `StateError` → telafi devreye girer, kullanıcının
      // günlüğü silinmez (eski sürümdeki "yarım import" senaryosunun
      // tam tersi).
      stage = 'favorite_foods';
      final newFavorites = await _insertBatched(
        'favorite_foods',
        _linkedRows(plan.favorites, plan.existingFavoriteNames, foodIdByName,
            'favorite_foods'),
      );
      counts['favorite_foods'] = newFavorites.length;
      if (newFavorites.isNotEmpty) {
        written['favorite_foods'] =
            newFavorites.map((r) => r['id'].toString()).toList();
      }

      stage = 'recent_foods';
      final newRecents = await _insertBatched(
        'recent_foods',
        _linkedRows(plan.recents, plan.existingRecentNames, foodIdByName,
            'recent_foods'),
      );
      counts['recent_foods'] = newRecents.length;
      if (newRecents.isNotEmpty) {
        written['recent_foods'] =
            newRecents.map((r) => r['id'].toString()).toList();
      }

      // 4) notification_preferences.
      stage = 'notification_preferences';
      final newPrefs = await _insertBatched(
        'notification_preferences',
        [
          for (final r in plan.notificationPrefs)
            if (!plan.existingNotificationTypes.contains(r.dedupKey)) r.values,
        ],
      );
      counts['notification_preferences'] = newPrefs.length;
      if (newPrefs.isNotEmpty) {
        written['notification_preferences'] =
            newPrefs.map((r) => r['id'].toString()).toList();
      }

      return ImportReport(
        counts: counts,
        skipped: plan.skipped,
        issues: plan.issues,
        coerced: plan.coerced,
      );
    } catch (error, stackTrace) {
      final code = error is PostgrestException ? error.code : null;
      AppLog.e(
        'Yedek içe aktarma "$stage" adımında durdu; telafi ediliyor',
        error,
        stackTrace,
      );
      // Telafi. Başarılıysa **hiçbir kayıt kalmaz**: `counts` sıfırlanır ve
      // kullanıcıya "0 kayıt eklendi, yedek yarım uygulanmadı" görünür.
      // Başarısızsa kalan satırların id'leri `survivors` içinde **tek tek**
      // sayılır — "kısmi sonuç" varsayımı yapılmaz, ölçülür.
      final survivors = <String, List<String>>{};
      for (final entry in written.entries) {
        if (entry.value.isNotEmpty) survivors[entry.key] = entry.value;
      }
      final rolledBack = await _rollback(written, survivors);
      if (rolledBack) {
        for (final t in survivors.keys) {
          counts[t] = 0;
        }
      }
      final report = ImportReport(
        counts: counts,
        skipped: plan.skipped,
        issues: plan.issues,
        coerced: plan.coerced,
        failedStage: stage,
        rolledBack: rolledBack,
        // Telafi başarısızsa **kalan** satırlar raporlanır; başarılıysa liste
        // boştur (hiçbir şey kalmadı).
        writtenTables: rolledBack ? const {} : survivors,
      );
      throw ImportWriteError(
        stage: stage,
        report: report,
        cause: error,
        stackTrace: stackTrace,
        code: code,
      );
    }
  }

  /// `favorite_foods` / `recent_foods` satırlarını `food_id`'si çözülmüş
  /// hâlde döndürür.
  ///
  /// Üç filtre:
  ///
  ///  * **DB'de zaten favorilenen gıda** (`existing…Names`) → tekrar
  ///    yazılmaz: `UNIQUE(user_id, food_id)` ihlali (`23505`) **tüm
  ///    import'u** düşürürdü.
  ///  * `foodIdByName`'de karşılığı olmayan gıda → `StateError`. Yedek
  ///    `foods`'ı yazıldıktan sonra bir ad bulunamıyorsa bu bir **iç
  ///    tutarsızlıktır** (`_idMapByBackupName` zaten eşleşmeyen
  ///    cevapta `StateError` fırlatır); sessizce `null` yazmak NOT NULL
  ///    ihlali ve tüm içe aktarmanın düşmesi demek.
  static List<Map<String, dynamic>> _linkedRows(
    List<PlannedRow> rows,
    Set<String> existingNames,
    Map<String, String> foodIdByName,
    String table,
  ) {
    final out = <Map<String, dynamic>>[];
    var unresolved = 0;
    for (final r in rows) {
      final name = r.backupName;
      if (name == null || existingNames.contains(name)) continue;
      final id = foodIdByName[name];
      if (id == null) {
        unresolved++;
        continue;
      }
      out.add({...r.values, 'food_id': id});
    }
    if (unresolved > 0) {
      throw StateError(
          '$table: gıda eşleştirilemedi ($unresolved satır) — '
          'gıda satırları yazıldı ama ad eşleşmesi tutmadı');
    }
    return out;
  }

  /// [importBatchSize]'lık dilimlerle toplu `insert` + `.select('id')`.
  ///
  /// Dönen satırlar **yazılan** satırlardır (telafi için id gerekir). Boş
  /// girdi **hiç istek atmaz** (`POST /tablo []` `PGRST102` verir).
  Future<List<Map<String, dynamic>>> _insertBatched(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    final out = <Map<String, dynamic>>[];
    for (final batch in _batches(rows, importBatchSize)) {
      // `insert(...)` varsayılanı `defaultToNull: true` → PostgREST gövdeyi
      // göndermeden önce `null` değerli **alanları düşürür** (`Prefer`
      // başlığını kaldırır, `postgrest_query_builder.dart:106-110`). Yani
      // `created_at: null` güvenlidir: alan gönderilmez ve DB'nin
      // `NOT NULL DEFAULT now()`'u devreye girer. Anahtar kümesi yine de
      // her dilimde sabittir (`PGRST102`).
      final res = await _client
          .from(table)
          .insert(_uniform(batch, _columnsOf(table)))
          .select('id');
      out.addAll(res);
    }
    return out;
  }

  /// O turda yazılan satırları **fiziksel olarak** siler.
  ///
  /// Telafi bir "yumuşak silme" değildir: içe aktarma yedekten türetilmiş
  /// satırlar ekliyordu, DB'de kullanıcının kendi kaydı yok; `DELETE`
  /// politikaları `auth.uid()` kapsamıyla var
  /// (`20260111041204_...sql:365/382/399`, `foods` için
  /// `20260927120000_...:75`), yani istemci kendi yazdığı satırları silebilir.
  ///
  /// `id` listesi de `in` filtresi olduğu için **dilimlenir** (2000 UUID tek
  /// sorguda ~78 KB → 414). Dönen değer: geri alınan tablo sayısı > 0 ise
  /// `true`; bir tablo silinemezse `false` (rapor `rolledBack = false`).
  Future<bool> _rollback(
    Map<String, List<String>> written,
    Map<String, List<String>> survivors,
  ) async {
    var allRolled = true;
    // Bağımlılık sırasının tersi: günlük kayıtlar → besin satırları → gıdalar.
    for (final table in importTables.reversed) {
      final ids = written[table];
      if (ids == null || ids.isEmpty) continue;
      var remaining = ids.length;
      for (final chunk in inFilterChunks(ids)) {
        try {
          await _client.from(table).delete().inFilter('id', chunk);
          remaining -= chunk.length;
        } catch (e, s) {
          AppLog.e('Telafi: $table silinemedi (${e.toString()})', e, s);
        }
      }
      if (remaining > 0) {
        allRolled = false;
        // Silinemeyen satırlar **kalan** olarak raporlanır (varsayım yok):
        // hangi dilimlerin sildiğini bilmiyoruz, bu yüzden en kötü senaryo
        // (hiçbiri silinmedi) varsayılır ve id'ler tam olarak raporlanır.
        survivors[table] = ids;
      }
    }
    return allRolled;
  }

  // ------------------------------------------------------------------
  // Satır dönüştürücüleri (saf)
  // ------------------------------------------------------------------

  /// `foods` yedeğini DB sözleşmesine göre beyaz listeler.
  ///
  /// **Beyaz liste uygulanır, kara liste değil.** Kara liste kullanan eski
  /// sürümde yedekteki tanınmayan her kolon (`barcode`, `last_synced_at`,
  /// `sync_state`, eski web istemcisinin eklediği alanlar) insert'e gönderiliyor
  /// ve PostgREST `PGRST204` ile **400** dönüyordu: "Could not find the
  /// 'column' in the schema cache". Bu, tek bozuk alanın **tüm içe aktarmayı**
  /// düşürmesidir.
  ///
  /// `verified` ve `popularity_count` **bilinçli olarak dışarıda**: ikisi de
  /// sistem tarafından türetilir (`popularity_count`'i
  /// `increment_food_popularity` trigger'ı artırır) ve web istemcisi de
  /// yedekten kopyalamayı reddeder (`src/hooks/useDataExport.ts:154`).
  /// `created_by` de dışarıda: her zaman oturumdaki kullanıcı yazılır.
  static Map<String, dynamic> _foodRow(
    Map<String, dynamic> food,
    String userId,
    String name,
    List<ImportIssue> issues,
    Map<String, int> coerced,
  ) {
    final out = <String, dynamic>{
      'name': name,
      'brand': _str(food['brand']),
      'serving_size_g': _positiveNum(food['serving_size_g']) ?? 100,
      'serving_description': _str(food['serving_description']),
      'source': _enumValue(
        food['source'],
        _sanitizeFoodSource,
        'manual',
        'source',
        'foods',
        food['id'],
        issues,
        coerced,
      ),
      'image_url': _str(food['image_url']),
      'created_by': userId,
    };
    return out;
  }

  /// `food_nutrition` yedeğini DB sözleşmesine göre beyaz listeler.
  ///
  /// `kcal/protein_g/carbs_g/fat_g` `NOT NULL` olduğu için sayısal olmayan
  /// (null/string) değer 0'a **çevrilmez** — önce 0'a çevrilip yazılıyordu ve
  /// sessizce yanlış besin değeri kaydediliyordu. Sayı değilse satır ölümcül
  /// ihlalle reddedilir (DB'nin de reddedeceği değer).
  ///
  /// `nova_score` `smallint` (yorum: 1..4). El yazımı bir yedek 10^9 gönderirse
  /// PostgREST 400 döner ve **tüm import** düşerdi; bu yüzden aralık dışı
  /// değer **NULL** bırakılır (kolon nullable) ve sayılır. Bkz.
  /// [_novaScore] — sayaç değeri buraya **yazılmaz**.
  ///
  static Map<String, dynamic> _nutritionRow(
    Map<String, dynamic> n,
    List<ImportIssue> issues,
    Map<String, int> coerced,
  ) {
    String num(String field) => _requireNum(
          n[field],
          field,
          'food_nutrition',
          n['food_id'],
          issues,
          finite: true,
        );
    final nova = _positiveNum(n['nova_score']);
    final row = <String, dynamic>{
      'per_100_g_ml': n['per_100_g_ml'] is bool ? n['per_100_g_ml'] : true,
      'kcal': num('kcal'),
      'protein_g': num('protein_g'),
      'carbs_g': num('carbs_g'),
      'fat_g': num('fat_g'),
      'fiber_g': _nonNegativeNum(n['fiber_g']),
      'sugar_g': _nonNegativeNum(n['sugar_g']),
      'salt_g': _nonNegativeNum(n['salt_g']),
      'saturated_fat_g': _nonNegativeNum(n['saturated_fat_g']),
      'trans_fat_g': _nonNegativeNum(n['trans_fat_g']),
      'nova_score': _novaScore(nova, coerced),
      'nutri_score': _str(n['nutri_score']),
    };
    return row;
  }

  /// `food_nutrition.nova_score` — `smallint` NULL, anlam aralığı 1..4
  /// (yorum: 1=İşlenmemiş … 4=Ultra işlenmiş, `full_setup.sql:707`).
  ///
  /// ## Düzeltilen hata (Tur 5, uçtan uca round-trip testi buldu)
  ///
  /// Eski sürümde aralık dışı/`null` değer şu ifadeyle yazılıyordu:
  /// `_count(coerced, 'food_nutrition.nova_score')` — **`_count` sayacın
  /// değerini döndürür**, yani 1, 2, 3 … `nova_score` olarak **yazılıyordu**.
  /// `nova_score` 0 olan (yani sınıflandırılmamış) bir gıda, import'ta
  /// **"1 = işlenmemiş"** olarak kaydediliyordu: kullanıcının gıdası
  /// yanlış sınıflandırılıyor ve bu hatayı **hiçbir test yakalamıyordu**
  /// (42 test yalnızca `coerced` sayacını doğruluyordu, gövdeyi değil).
  ///
  /// Doğrusu: geçersiz/eksik değer **NULL** bırakılır (`nova_score`
  /// nullable) ve yalnızca sayaç artar — kullanıcı "3 gıdanın NOVA
  /// sınıfı düzeltildi" bilgisini rapordan alır, veri ise **uydurulmaz**.
  static int? _novaScore(double? nova, Map<String, int> coerced) {
    if (nova == null) return null;
    if (nova >= 1 && nova <= 4) return nova.toInt();
    _count(coerced, 'food_nutrition.nova_score');
    return null;
  }

  /// `meal_entries` yedeğini beyaz listeler.
  ///
  /// `meal_type` ve `source` enum alanları: yedek bozuk/eskiden kalma bir
  /// değer taşırsa (`'brunch'`, `'barcode'`) insert CHECK ihlaliyle 400 döner
  /// ve **tüm içe aktarma** orada durur. Geçersiz değerler DB varsayılanına
  /// çekilir: `meal_type` → `'snack'`, `source` → `'manual'`.
  ///
  /// `food_id` yedeğin eski UUID'sidir → içe aktarımda kullanıcının yeni
  /// gıda id'siyle değiştirilir; karşılık yoksa `null` (manuel girdi).
  /// `created_at` yedeğin damgasıdır: toplu yazımda satır sırası `created_at`'i
  /// taşımadığı için tüm öğünler aynı `now()`'u alır ve eski sürümdeki
  /// "ekleme sırası" koruması kaybolur; damga gövdede taşınır.
  static Map<String, dynamic> _mealRow(
    Map<String, dynamic> m,
    String userId,
    List<ImportIssue> issues,
    Map<String, int> coerced,
  ) {
    final row = <String, dynamic>{
      'user_id': userId,
      'entry_date': _dateString(m['entry_date']) ??
          _requireStr(m['entry_date'], 'entry_date', 'meal_entries', m['id'], issues),
      'meal_type': _enumValue(
        m['meal_type'],
        mealTypeDbValues,
        'snack',
        'meal_type',
        'meal_entries',
        m['id'],
        issues,
        coerced,
      ),
      'food_id': m['food_id']?.toString(),
      'custom_name': _str(m['custom_name']),
      'amount_g_ml': _requireRange(
        m['amount_g_ml'],
        'amount_g_ml',
        'meal_entries',
        m['id'],
        issues,
        min: 0.0001,
        max: maxAmountGMl,
        finite: true,
      ),
      'calculated_kcal': _requireRange(
        m['calculated_kcal'],
        'calculated_kcal',
        'meal_entries',
        m['id'],
        issues,
        min: 0,
        max: 9999999,
        finite: true,
      ),
      'calculated_protein': _requireRange(
        m['calculated_protein'],
        'calculated_protein',
        'meal_entries',
        m['id'],
        issues,
        min: 0,
        max: 9999999,
        finite: true,
      ),
      'calculated_carbs': _requireRange(
        m['calculated_carbs'],
        'calculated_carbs',
        'meal_entries',
        m['id'],
        issues,
        min: 0,
        max: 9999999,
        finite: true,
      ),
      'calculated_fat': _requireRange(
        m['calculated_fat'],
        'calculated_fat',
        'meal_entries',
        m['id'],
        issues,
        min: 0,
        max: 9999999,
        finite: true,
      ),
      'note': _str(m['note']),
      'photo_url': _str(m['photo_url']),
      'source': _enumValue(
        m['source'],
        _sanitizeFoodSource,
        'manual',
        'source',
        'meal_entries',
        m['id'],
        issues,
        coerced,
      ),
      'created_at': _createdAt(m['created_at']),
    };
    return row;
  }

  /// `water_entries` yedeğini beyaz listeler.
  ///
  /// `amount_ml` `INTEGER NOT NULL` olduğu için küsüratlı/string değer 400
  /// üretir: küsüratlı değer **yuvarlanır** (250.4 → 250), tam sayı olmayan
  /// (string/null/NaN) değer ise ölümcül ihlaldir. Eski sürüm bunları `0`'a
  /// çeviriyordu ve `water_entries_amount_positive` CHECK'i (`full_setup.sql:618`)
  /// 400 döndürüyordu → **mevcut öğünler yazıldıktan sonra** import su
  /// adımında ölüyordu.
  static Map<String, dynamic> _waterRow(
    Map<String, dynamic> w,
    String userId,
    WaterInstant when,
    List<ImportIssue> issues,
    Map<String, int> coerced,
  ) {
    final raw = w['amount_ml'];
    var ml = 0;
    if (raw is num && raw.isFinite) {
      final rounded = raw.round();
      if (rounded > 0 && rounded <= maxAmountMl) {
        ml = rounded;
        if (rounded != raw) _count(coerced, 'water_entries.amount_ml');
      }
    }
    if (ml == 0) {
      issues.add(ImportIssue(
        table: 'water_entries',
        rowId: w['id']?.toString(),
        field: 'amount_ml',
        message: 'Su miktarı $maxAmountMl ml aralığında değil '
            '(DB CHECK: amount_ml > 0 AND amount_ml <= $maxAmountMl)',
        isFatal: true,
      ));
    }
    return {
      'user_id': userId,
      'entry_date': when.day,
      'entry_time': when.iso,
      'amount_ml': ml,
      'created_at': _createdAt(w['created_at']),
    };
  }

  /// `weight_entries` yedeğini beyaz listeler — `weight_kg NUMERIC(5,2) NOT NULL`
  /// ve `weight_entries_weight_range` CHECK (`full_setup.sql:620`).
  ///
  /// Eski sürüm geçersiz kilo için `0.0` yazıyordu; DB `0 > 0` CHECK'ini
  /// reddedip **tüm import'u** düşürüyordu (öğünler ve su kayıtları yazılmış
  /// hâlde). Artık ölümcül ihlal → **hiçbir şey yazılmadan** durur.
  static Map<String, dynamic> _weightRow(
    Map<String, dynamic> w,
    String userId,
    String day,
    List<ImportIssue> issues,
    Map<String, int> coerced,
  ) {
    final kg = _requireRange(
      w['weight_kg'],
      'weight_kg',
      'weight_entries',
      w['id'],
      issues,
      min: 0.0001,
      max: maxWeightKg,
      finite: true,
    );
    return {
      'user_id': userId,
      'entry_date': day,
      'weight_kg': kg,
      'note': _str(w['note']),
      'created_at': _createdAt(w['created_at']),
    };
  }

  /// `favorite_foods` / `recent_foods` yedeğini beyaz listeler.
  ///
  /// **`user_id` her kayıtta yazılır** (yedeğin değeri yok sayılır): RLS'in
  /// INSERT politikası `WITH CHECK (auth.uid() = user_id)`
  /// (`full_setup.sql:332/337`). Kolon gövdeden düşürülürse (`insert`
  /// varsayılanı `defaultToNull: true`) DB `NOT NULL` ihlali 400 döner ve
  /// **tüm içe aktarma** düşer — aynı tuzak `meal_entries`'te de geçerli.
  ///
  /// `food_id` **yazılmaz**: `PlannedRow.backupName` (gıda adı) üzerinden
  /// yeni gıda id'sine çevrilir, çünkü yedeğin `food_id`'si eski bir
  /// UUID'dir ve `meal_entries`/`food_nutrition` ile aynı sebepten
  /// kullanılamaz. Kolon atlandığı için PostgREST `food_id`'yi gövdeden
  /// düşürür — bu yüzden satır `backupName`'den doldurulmadan
  /// **yazılmamalıdır** ([_apply] `unresolved` kontrolü).
  ///
  /// `recent_foods.use_count` DB'de `INTEGER DEFAULT 1` — negatif/çok
  /// büyük değer yazmak yerine `>= 1` aralığına çekilir ve sayılır.
  /// `last_used_at` gerçekçi değilse `null` → DB `now()` devreye girer.
  static Map<String, dynamic> _foodLinkRow(
    Map<String, dynamic> f,
    String userId,
    String table,
    List<ImportIssue> issues,
    Map<String, int> coerced,
  ) {
    // `created_at` **her iki tabloda da** yazılır: toplu `insert` sabit
    // anahtar kümesi ister (`_uniform`/`PGRST102`) ve `favorite_foods`
    // için favoriye ekleme sırasını korur. `recent_foods` sıralaması
    // `last_used_at` üzerinden olduğu için `created_at` burada yalnız
    // sözleşme kolonudur.
    final row = <String, dynamic>{
      'user_id': userId,
      'created_at': _createdAt(f['created_at']),
    };
    if (table == 'recent_foods') {
      row.addAll(<String, dynamic>{
        'last_used_at': _createdAt(f['last_used_at']),
        'use_count': _useCount(f['use_count'], table, issues, coerced),
      });
    }
    return row;
  }

  /// `recent_foods.use_count` — `INTEGER`, DB varsayılanı 1.
  ///
  /// CHECK kısıtı **yok**, ama negatif değer "hiç kullanılmamış" anlamına
  /// gelir ve sıralamayı bozar; 1..1e6 aralığı dışındaki değer 1'e çekilir
  /// ve **sayar** (boş/null değer **sayılmaz**: DB varsayılanı da 1).
  static int _useCount(
    Object? v,
    String table,
    List<ImportIssue> issues,
    Map<String, int> coerced,
  ) {
    if (v == null) return 1;
    if (v is num && v.isFinite) {
      final n = v.toInt();
      if (n >= 1 && n <= 1000000) {
        if (n != v) _count(coerced, '$table.use_count');
        return n;
      }
    }
    _count(coerced, '$table.use_count');
    return 1;
  }

  /// `notification_preferences` yedeğini beyaz listeler.
  ///
  /// DB CHECK'leri (`20260927120000_...:415-423`):
  /// `start_hour`/`end_hour`/`summary_hour` ∈ 0..23,
  /// `interval_hours` ∈ 1..24, `summary_day` ∈ 0..6.
  /// Aralık dışı değer DB 400 döndürür ve **tüm import'u** düşürürdü;
  /// bu yüzden DB varsayılanına çekilir ve `coerced` sayacı artar
  /// ("3 bildirim tercihinde saat düzeltildi").
  static Map<String, dynamic> _notificationPrefRow(
    Map<String, dynamic> n,
    String userId,
    String type,
    List<ImportIssue> issues,
    Map<String, int> coerced,
  ) {
    int hour(String field, int fallback) =>
        _hour(n[field], field, fallback, issues, coerced);
    return {
      'user_id': userId,
      'notification_type': type,
      'push_enabled': _bool(n['push_enabled'], fallback: true),
      'email_enabled': _bool(n['email_enabled'], fallback: true),
      'start_hour': hour('start_hour', 9),
      'end_hour': hour('end_hour', 21),
      'interval_hours': _clampInt(
        n['interval_hours'],
        'interval_hours',
        1,
        24,
        3,
        issues,
        coerced,
      ),
      'summary_day': _clampInt(n['summary_day'], 'summary_day', 0, 6, 1, issues, coerced),
      'summary_hour': hour('summary_hour', 9),
    };
  }

  /// `0..23` saat aralığı — DB CHECK `start_hour BETWEEN 0 AND 23`.
  static int _hour(
    Object? v,
    String field,
    int fallback,
    List<ImportIssue> issues,
    Map<String, int> coerced,
  ) =>
      _clampInt(v, field, 0, 23, fallback, issues, coerced);

  /// Aralık dışı tam sayıyı DB varsayılanına çeker ve **sayar**.
  static int _clampInt(
    Object? v,
    String field,
    int min,
    int max,
    int fallback,
    List<ImportIssue> issues,
    Map<String, int> coerced,
  ) {
    if (v is num && v.isFinite) {
      final n = v.toInt();
      if (n >= min && n <= max) {
        if (n != v) _count(coerced, 'notification_preferences.$field');
        return n;
      }
    }
    _count(coerced, 'notification_preferences.$field');
    return fallback;
  }

  /// Yedeğin boolean alanı — yalnızca gerçek `bool` kabul edilir.
  ///
  /// Yedekte `"true"`/`1` gibi bir dize gelirse DB'ye **dize** yazılır ve
  /// Postgres `22P02` döndürür (tüm import düşer). Sessizce `true`
  /// varsayılanına çekmek kullanıcının tercihini yanlış kaydeder; bu
  /// yüzden dize sayılır (`coerced`) ve varsayılan kullanılır.
  static bool _bool(Object? v, {required bool fallback}) {
    if (v is bool) return v;
    return fallback;
  }

  // ------------------------------------------------------------------
  // Saf alan yardımcıları
  // ------------------------------------------------------------------

  /// `food_source` enum değerleri (`20260822000000_remove_barcode.sql`).
  static const Set<String> _sanitizeFoodSource = {'photo', 'text', 'manual'};

  /// `notification_preferences.notification_type` DB CHECK allow-list'i
  /// (`notification_preferences_type_allowlist`,
  /// `20260927120000_security_hardening_round1.sql:411-413`).
  ///
  /// Bu tablo dışa aktarılıyordu ama içe aktarılmıyordu; eklenirken CHECK
  /// dışı bir tür 400 döndürür ve **tüm import'u** düşürürdü.
  static const Set<String> _notificationTypeDbValues = {
    'weigh_in',
    'daily_log',
    'water',
    'goal_achieved',
    'weekly_summary',
  };

  /// `importData` sırasında yazılan/yazılabilecek tablolar — sıra **bağımlılık
  /// sırasıdır** (`foods` → `food_nutrition` → günlük kayıtlar →
  /// favoriler/son kullanılanlar → bildirim tercihleri) ve telafi
  /// bu sıranın tersinde yürür.
  ///
  /// ## `favorite_foods` / `recent_foods` neden sonra?
  ///
  /// İkisi de `food_id UUID NOT NULL REFERENCES foods(id)` FK'si taşır
  /// (`full_setup.sql:185-203`, `20260111041204_...sql:261-282`).
  /// `food_id` **nullable DEĞİL** — yani öğünlerdeki gibi `null` bırakıp
  /// "manuel girdi" fallback'i **yoktur**: eşleşmeyen bir favoriyi
  /// sessizce düşürmek yerine ölümcül bulgu üretmek ya da tabloyu
  /// hiç yazmamak gerekir. Karar: eşleşmeyen favoriler **atlanır ve
  /// raporlanır** (bkz. [ImportReport.skipped]) — ölümcül olsaydı tek
  /// eski-kopmuş bir favori, kullanıcının tüm yedeğini geri yüklemesini
  /// engellerdi (P1 veri kaybı → P0'a yükselirdi).
  ///
  /// FK nedeniyle `foods` **önce** yazılmalıdır. Telafi ters sırada yürür:
  /// favoriler önce silinir, sonra `foods` — aksi hâlde `ON DELETE CASCADE`
  /// zaten silmiş olurdu ama `written` defterinde ölü id kalırdı.
  static const List<String> importTables = <String>[
    'foods',
    'food_nutrition',
    'meal_entries',
    'water_entries',
    'weight_entries',
    'favorite_foods',
    'recent_foods',
    'notification_preferences',
  ];

  /// Toplu `insert`'te gönderilecek kolonlar.
  ///
  /// PostgREST çok satırlı `POST`'ta **tüm nesnelerin anahtar kümesinin aynı
  /// olmasını şart koşar** (`PGRST102` — "All object keys must match"). Bu
  /// yüzden her tablo için sabit bir kolon listesi vardır ve her satır o
  /// listenin **tamamına** sahiptir (null değerler de yazılır).
  static const Map<String, List<String>> _insertColumns = <String, List<String>>{
    'foods': <String>[
      'name',
      'brand',
      'serving_size_g',
      'serving_description',
      'source',
      'image_url',
      'created_by',
    ],
    'food_nutrition': <String>[
      'food_id',
      'per_100_g_ml',
      'kcal',
      'protein_g',
      'carbs_g',
      'fat_g',
      'fiber_g',
      'sugar_g',
      'salt_g',
      'saturated_fat_g',
      'trans_fat_g',
      'nova_score',
      'nutri_score',
    ],
    'meal_entries': <String>[
      'user_id',
      'entry_date',
      'meal_type',
      'food_id',
      'custom_name',
      'amount_g_ml',
      'calculated_kcal',
      'calculated_protein',
      'calculated_carbs',
      'calculated_fat',
      'note',
      'photo_url',
      'source',
      'created_at',
    ],
    'water_entries': <String>[
      'user_id',
      'entry_date',
      'entry_time',
      'amount_ml',
      'created_at',
    ],
    'weight_entries': <String>[
      'user_id',
      'entry_date',
      'weight_kg',
      'note',
      'created_at',
    ],
    // `favorite_foods`: `user_id` **her kayıtta** yazılır. RLS'in INSERT
    // politikası `WITH CHECK (auth.uid() = user_id)`
    // (`full_setup.sql:332`) — kolon gövdeden düşürülürse (`defaultToNull:
    // true`) `user_id` NOT NULL ihlali 400 döner ve **tüm import** düşer.
    'favorite_foods': <String>[
      'user_id',
      'food_id',
      'created_at',
    ],
    // `recent_foods`: aynı RLS mantığı (`full_setup.sql:337`). `food_id`
    // UPDATE'te değiştirilemez (`freeze_recent_foods_food_id` trigger'ı
    // `42501` fırlatır) — bu yüzden yalnızca INSERT yolumuz var.
    'recent_foods': <String>[
      'user_id',
      'food_id',
      'last_used_at',
      'use_count',
    ],
    'notification_preferences': <String>[
      'user_id',
      'notification_type',
      'push_enabled',
      'email_enabled',
      'start_hour',
      'end_hour',
      'interval_hours',
      'summary_day',
      'summary_hour',
    ],
  };

  static List<String> _columnsOf(String table) =>
      _insertColumns[table] ??
      (throw StateError('Bilinmeyen içe aktarma tablosu: $table'));

  /// Her satırı tablonun **sabit** kolon kümesine eşitler.
  ///
  /// PostgREST çok satırlı `POST`'ta anahtar kümelerinin aynı olmasını şart
  /// koşar (`PGRST102` — "All object keys must match"), bu yüzden anahtar
  /// kümesi **tablodan** gelir, satırdan değil: her satır tam kolon kümesine
  /// sahiptir. Eksik kolon sözleşmeyi ihlal eder ve `StateError` fırlatır
  /// (sessiz `PGRST102` yerine, nerede bozulduğu belli olur).
  ///
  /// `null` değerli alanlar **yazılır** — Postgres `DEFAULT`'i değil `NULL`'ı
  /// alır. Bu yüzden `created_at` gibi `NOT NULL DEFAULT now()` kolonlarda
  /// `null` gönderilmez: [_stampOf] geçersiz damga için `null` döner ve
  /// [_insertBatched] o satırları **damgasız** ayrı dilimlere koyar.
  static List<Map<String, dynamic>> _uniform(
    List<Map<String, dynamic>> rows,
    List<String> columns,
  ) {
    if (rows.isEmpty) return const [];
    for (final r in rows) {
      for (final c in columns) {
        if (!r.containsKey(c)) {
          throw StateError(
            'Toplu insert satırı "$c" kolonunu içermiyor — tablo sözleşmesi '
            'ile satır kümesi ayrışmış (beklenen: $columns)',
          );
        }
      }
    }
    return [
      for (final r in rows)
        <String, dynamic>{for (final c in columns) c: r[c]},
    ];
  }

  /// [values] listesini [size] boyutunda dilimlere böler.
  ///
  /// Boş girdi **hiç dilim üretmez**: PostgREST'e `[]` göndermek
  /// `PGRST102` ("All object keys must match") verir.
  static List<List<T>> _batches<T>(List<T> values, int size) {
    if (values.isEmpty) return const [];
    return [
      for (var i = 0; i < values.length; i += size)
        values.sublist(i, (i + size).clamp(0, values.length)),
    ];
  }

  /// Dönen satırların `id`'lerini **plan sırasına** göre geri eşler.
  ///
  /// Postgres `INSERT … RETURNING` satırları giriş sırasıyla döndürür, ancak
  /// buna güvenmek yerine **ad** üzerinden eşleme yapılır: dedup zaten ad
  /// bazlıdır ve plan içinde adlar benzersizdir. Sıra bozulsa bile yanlış
  /// gıda `food_id`'si yazılmaz.
  static Map<String, String> _idMapByBackupName(
    List<PlannedRow> plan,
    List<Map<String, dynamic>> inserted,
  ) {
    if (inserted.length != plan.length) {
      throw StateError(
          'Gıda ekleme cevabı beklenmedik: ${inserted.length}/${plan.length}');
    }
    final ids = <String, String>{};
    for (var i = 0; i < plan.length; i++) {
      final id = inserted[i]['id'];
      final name = plan[i].backupName;
      if (id != null && name != null) ids[name] = id.toString();
    }
    return ids;
  }

  /// Yedeğin `meal_entries` dedup anahtarları
  /// (`entry_date|custom_name|meal_type`).
  ///
  /// Saf yardımcı — içe aktarma yolunda `buildImportPlan` tarafından kullanılır
  /// ama sözleşmesi testte doğrulanır: anahtar biçimi değişirse dedup sessizce
  /// bozulur.
  static List<String> mealKeysOf(List<Map<String, dynamic>> rows) {
    final out = <String>{};
    for (final m in rows) {
      final k = _mealKey(m);
      if (k != null) out.add(k);
    }
    return out.toList();
  }

  /// [values] listesini [inFilterChunkSize] boyutunda dilimlere böler.
  ///
  /// Boş girdi **tek boş dilim** döndürür, yani çağıran `if (isNotEmpty)`
  /// kontrolü yapmasa bile `in.()` üretmez (PostgREST bunu `PGRST100`
  /// "Syntax error" ile reddeder).
  static List<List<T>> inFilterChunks<T>(List<T> values) {
    if (values.isEmpty) return const [];
    return [
      for (var i = 0; i < values.length; i += inFilterChunkSize)
        values.sublist(i, (i + inFilterChunkSize).clamp(0, values.length)),
    ];
  }

  /// Satır yumuşak silinmiş mi (`deleted_at` dolu)?
  ///
  /// Yumuşak silinen kayıt yedekten **yeniden eklenmez**. Yedek `exportData`
  /// tarafından üretildiğinde zaten `deleted_at IS NULL` süzgecinden geçer,
  /// ancak elle düzenlenmiş bir yedek silinmiş satırlar içerebilir; eski
  /// sürüm onları **yeniden "canlandırıyordu** (yeni `id` ile `deleted_at` boş
  /// bir satır) ve kullanıcı ilk sildiği öğünü geri buluyordu. Üç tablo
  /// (`meal_entries`, `water_entries`, `weight_entries`) yumuşak silme kullanır;
  /// `foods` tablosunda `deleted_at` kolonu yoktur; eksik alan silinmemiş
  /// sayılır.
  @visibleForTesting
  static bool isDeleted(Map<String, dynamic> row) {
    final v = row['deleted_at'];
    if (v == null) return false;
    if (v is String) return v.isNotEmpty;
    return true;
  }

  /// Yedekteki tablo satırlarını `Map<String, dynamic>` listesine çevirir.
  ///
  /// Bozuk girdi (null / liste değil) **hata fırlatmaz**, boş liste sayılır:
  /// kullanıcı el yazımı bir yedekte `meal_entries: "abc"` yazdıysa import
  /// bu tabloyu atlayıp devam etmelidir, çökmemelidir.
  static List<Map<String, dynamic>> _rowsOf(Object? raw) {
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final row in raw) {
      if (row is Map) out.add(Map<String, dynamic>.from(row));
    }
    return out;
  }

  /// Yumuşak silinmiş satırları ayıklar (bkz. [isDeleted]).
  static List<Map<String, dynamic>> _liveRowsOf(Object? raw) =>
      _rowsOf(raw).where((row) => !isDeleted(row)).toList();

  static void _skip(
    ImportPlan plan,
    String table,
    List<ImportIssue> issues,
    String field,
    String message,
    Object? rowId,
  ) {
    plan.skipped[table] = (plan.skipped[table] ?? 0) + 1;
    issues.add(ImportIssue(
      table: table,
      rowId: rowId?.toString(),
      field: field,
      message: message,
    ));
  }

  static int _count(Map<String, int> counter, String key) {
    counter[key] = (counter[key] ?? 0) + 1;
    return counter[key]!;
  }

  static String? _str(Object? v) {
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    return null;
  }

  /// DB'nin `NUMERIC`/CHECK sözleşmesine **girmeyen** zorunlu sayısal alan.
  ///
  /// Ölümcül ihlal üretir: eski sürüm `0`'a çeviriyordu ve DB 400 döndürüp
  /// **tüm import'u** düşürüyordu (kısmi yazmış hâlde).
  static double _requireRange(
    Object? v,
    String field,
    String table,
    Object? rowId,
    List<ImportIssue> issues, {
    required double min,
    required double max,
    bool finite = true,
  }) {
    if (v is num) {
      final d = v.toDouble();
      final okValue = finite ? d.isFinite : !d.isNaN;
      if (okValue && d >= min && d <= max) return d;
    }
    issues.add(ImportIssue(
      table: table,
      rowId: rowId?.toString(),
      field: field,
      message: '$field DB sözleşmesinin dışında ($min < değer <= $max olmalı)',
      isFatal: true,
    ));
    return min;
  }

  static String _requireNum(
    Object? v,
    String field,
    String table,
    Object? rowId,
    List<ImportIssue> issues, {
    bool finite = true,
  }) {
    if (v is num) {
      final d = v.toDouble();
      if ((!finite || d.isFinite) && d >= 0) {
        return finite ? d.toString() : d.toString();
      }
    }
    issues.add(ImportIssue(
      table: table,
      rowId: rowId?.toString(),
      field: field,
      message: '$field sayı değil (DB NOT NULL numeric)',
      isFatal: true,
    ));
    return '0';
  }

  static String _requireStr(
    Object? v,
    String field,
    String table,
    Object? rowId,
    List<ImportIssue> issues,
  ) {
    final s = _str(v);
    if (s != null) return s;
    issues.add(ImportIssue(
      table: table,
      rowId: rowId?.toString(),
      field: field,
      message: '$field boş veya çözümlenemedi',
      isFatal: true,
    ));
    return '1970-01-01';
  }

  /// ENUM/CHECK alanı — geçersizse DB varsayılanına çekilir ve sayılır.
  static String _enumValue(
    Object? v,
    Set<String> allowed,
    String fallback,
    String field,
    String table,
    Object? rowId,
    List<ImportIssue> issues,
    Map<String, int> coerced,
  ) {
    if (v is String && allowed.contains(v)) return v;
    _count(coerced, '$table.$field');
    return fallback;
  }

  static double? _positiveNum(Object? v) {
    if (v is num) {
      final d = v.toDouble();
      if (d.isFinite && d > 0) return d;
    }
    return null;
  }

  static double? _nonNegativeNum(Object? v) {
    if (v is num) {
      final d = v.toDouble();
      if (d.isFinite && d >= 0) return d;
    }
    return null;
  }

  /// `yyyy-MM-dd` dizesi üretir; `Date`/`DateTime`/ISO dizesi kabul eder.
  static String? _dateString(Object? v) {
    if (v is DateTime) {
      final u = v.toUtc();
      return '${u.year.toString().padLeft(4, '0')}-'
          '${u.month.toString().padLeft(2, '0')}-'
          '${u.day.toString().padLeft(2, '0')}';
    }
    if (v is! String) return null;
    final t = v.trim();
    if (t.length < 8) return null;
    final parsed = DateTime.tryParse(t);
    if (parsed == null) return null;
    return '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}';
  }

  /// Yedekteki `created_at` damgasını taşır (toplu yazım sıra koruması).
  ///
  /// Gerçekçi olmayan damgalar (2000 öncesi, gelecek) yok sayılır: DB
  /// `now()` varsayılanı yazılır. Böylece el yazımı bir yedekteki bozuk
  /// tarih **tüm günlük ekranını** bozamaz.
  static String? _createdAt(Object? v) {
    if (v is! String) return null;
    final parsed = DateTime.tryParse(v.trim());
    if (parsed == null) return null;
    if (parsed.year < 2000) return null;
    if (parsed.isAfter(DateTime.now().toUtc().add(const Duration(days: 1)))) {
      return null;
    }
    return parsed.toUtc().toIso8601String();
  }

  static int? _epochMicros(Object? v) {
    if (v is DateTime) return v.toUtc().millisecondsSinceEpoch * 1000;
    if (v is! String) return null;
    final parsed = DateTime.tryParse(v.trim());
    if (parsed == null) return null;
    return parsed.toUtc().millisecondsSinceEpoch * 1000;
  }

  /// Su kaydının zaman damgası + günü. `entry_time` yoksa `entry_date`
  /// kullanılır (web `localDateFromIso` davranışının tersi) ve bu türetme
  /// sayacla bildirilir.
  static WaterInstant? _waterInstant(
    Map<String, dynamic> w,
    List<ImportIssue> issues,
    Map<String, int> coerced,
  ) {
    final micros = _epochMicros(w['entry_time']);
    final day = _dateString(w['entry_date']);
    if (micros == null) {
      if (day == null) return null;
      // Saat bilgisi yok: günün başlangıcı kullanılır ve türetme raporlanır.
      _count(coerced, 'water_entries.entry_time');
      final parsed = DateTime.tryParse('${day}T00:00:00Z');
      if (parsed == null) return null;
      return WaterInstant(
        micros: parsed.toUtc().millisecondsSinceEpoch * 1000,
        iso: parsed.toUtc().toIso8601String(),
        day: day,
      );
    }
    return WaterInstant(
      micros: micros,
      iso: DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true)
          .toIso8601String(),
      day: day ?? formatUtcDateFromMicros(micros),
    );
  }

  /// UTC damga → `yyyy-MM-dd`.
  static String formatUtcDateFromMicros(int micros) {
    final d = DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// `null` → anahtarsız (import'ta atlanacak satır).
  static String? _mealKey(Map<String, dynamic> m) {
    final date = m['entry_date'];
    final type = m['meal_type'];
    if (date is! String || date.isEmpty) return null;
    if (type is! String || type.isEmpty) return null;
    final name = (m['custom_name'] ?? '') as String;
    return '$date|$name|$type';
  }

  // --- yedek döndürme uyumluluğu -------------------------------------

  /// Geriye dönük uyum: eski çağıranlar tek bir gıdayı beyaz listelemek için
  /// [sanitizeFood] kullanıyordu.
  ///
  /// Artık her satır **sabit** kolon kümesiyle üretiliyor (toplu `insert`
  /// `PGRST102`'yi kırmasın diye) ve `null` alanlar PostgREST tarafından
  /// gönderilmeden düşürülür (`defaultToNull: true` varsayılanı). Bu
  /// sarmalayıcı eski sözleşmenin **gözlenen** kısmını korur: `null` alanlar
  /// anahtarda görünmez. İçe aktarma yolu artık bu metotu kullanmaz, [_foodRow]
  /// kullanır.
  static Map<String, dynamic> sanitizeFood(Map<String, dynamic> food) {
    final name = food['name'];
    final issues = <ImportIssue>[];
    final coerced = <String, int>{};
    final key = name is String && name.trim().isNotEmpty
        ? name.trim()
        : (name?.toString() ?? '');
    final row =
        _foodRow(food, _str(food['created_by']) ?? '', key, issues, coerced);
    return <String, dynamic>{
      for (final e in row.entries)
        if (e.value != null) e.key: e.value,
    };
  }
}

final dataTransferRepositoryProvider = Provider<DataTransferRepository>((ref) {
  return DataTransferRepository(ref.watch(supabaseClientProvider));
});

/// Oturum açık kullanıcı id kısayolu.
String? currentUserId(Ref ref) => ref.watch(currentUserProvider)?.id;

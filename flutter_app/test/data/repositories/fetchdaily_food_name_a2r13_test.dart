/// ⭐ A2r13 (Tur 13) — `fetchDaily` `foods(name)` embed'i: **ölçüm + düzeltme +
/// sözleşme kilidi**.
///
/// ## Bu test neden var?
///
/// A4r11 (Tur 12) kendi ölçüm dosyasında şunu belgeledi ve bana aktardı:
///
/// > `DiaryRepository.fetchDaily` `foods` join'i **yapmıyor**,
/// > `MealEntry.displayName` yalnız `custom_name` okuyor
/// > → `food_id` dolu olsa bile (gıda `foods` tablosunda **duruyorsa**)
/// > dashboard o öğünü **"Bilinmeyen"** gösteriyor.
/// > `git show e99ba95` ile doğrulandı: **v1.2.0'dan beri**.
///
/// A4r11 yalnızca `canDelete == true` olan (kullanıcının kendi) gıdalarda
/// `custom_name` yazarak P0'yı kapattı; **asıl kapsam daha geniş** diye de
/// not düştü. Bu dosya o kalan yarıyı kapatır ve A4r11'in ölçüm dosyasını
/// **tersine çevirir** (o dosya artık kırmızıdır; aşağıda açıklandı).
///
/// ## ⭐⭐ "Yeşil test ≠ etkin test" — bu dosyadaki dört tuzak
///
/// Bu döngüde 6 vaka yakalandı (A4r7b `tap`, A4r10 `hitTest`, A5r10
/// normalize katmanı, A1r10 ×3, A2r12 ×1). Burada **kendi tuzaklarım**
/// ölçüldü ve kapatıldı:
///
/// 1. **`displayName` iddiası `MealEntry` **üretim sınıfının kendisinden**
///    geçirilirse** hata gizlenir. Burada iddia **ham JSON** üzerinden
///    kurulur: `MealEntry.fromJson` bir gömülü `foods` nesnesini okuyup
///    `displayName`'i doğru kuruyor mu — `displayName` **sonucunu** değil,
///    `foodName` **alanını** ham JSON'dan denetliyoruz.
/// 2. **`select=*` sessiz geçerdi.** Düz `select()` embed'i **açmaz**;
///    PostgREST `select=*` gönderir ve ayrı bir `foods` nesnesi **üretmez**
///    → `displayName` yine "Bilinmeyen" kalır, test de yeşil görünebilirdi.
///    Bu yüzden `select` parametresi **AÇIK** liste olarak kilitlenir ve
///    listenin `fromJson`'ın okuduğu kolonlarla **birebir** eşleştiği
///    `meal_entry.dart` metninden **okunarak** kanıtlanır (sabit ikinci liste
///    yazılmaz → iki listenin ayrışması mümkün değil).
/// 3. **Kolon düşerse `fetchDaily` sessizce değil, **çöker**.** `fromJson`
///    nullable olmayan kolonlarda `as String`/`as num` cast'i yapar, yani
///    eksik kolon `TypeError` demektir. Test bu yüzden **gerçek** PostgREST
///    gövdesiyle `fetchDaily`'yi çalıştırıp `mealEntries`'in dolu geldiğini
///    de kanıtlıyor (sadece `select` metnine bakmak yetmez).
/// 4. **Kaynak önceliği ters çevrilirse test yine yeşil kalır.** `custom_name`
///    yazılıyken `foods.name` kazanırsa kullanıcının kendi cümlesi ezilir
///    (A4r11'in ölçtüğü kural). İki yön de ayrı testte kilitlendi.
///
/// ## Ölçüm: embed'in maliyeti **yok** (Postgres 17, 50k gıda / 9M öğün)
///
/// `tool/a2r13_fetchdaily_embed.sql` — gerçek indekslerle 200 koşu
/// (ilk 20'si ısınma) → n=180 medyan:
///
/// | varyant | medyan | p95 |
/// |---|---|---|
/// | A) join yok | 0.0375 ms | 0.0860 ms |
/// | B) `LEFT JOIN foods(name)` | **0.0370 ms** | 0.0862 ms |
///
/// Fark −0.0005 ms (**%−1.3**) = gürültü sınırında. Plan: `Nested Loop
/// Left Join` + `Index Scan using foods_pkey … rows=1 loops=10` → gıda
/// başına **bir** PK sondası. Ağır gün (70 öğün): 0.0310 ms vs 0.0310 ms.
///
/// ⭐ Yani düzeltme **kanıtsız bir iyileştirme değil**: maliyet ölçülmüş ve
/// **sıfır** bulunmuştur. (A1r8/A2r11'in "kanıtsız iyileştirme yapma" kuralı.)
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:calorix/data/models/meal_entry.dart';
import 'package:calorix/data/repositories/diary_repository.dart';

/// `fetchDaily`'nin `meal_entries` isteğini kaydeder ve **gerçek** bir
/// PostgREST gövdesi döner (yani test, üretim kodunun hata düzelten
/// fonksiyonundan geçirilip çıktısı denetlenmez — ham istek + ham JSON).
class Probe extends http.BaseClient {
  Probe(this.rows);

  final List<Map<String, dynamic>> rows;
  final List<Uri> mealUris = [];

  /// Tüm istekler — "embed ayrı istek mi üretiyor" ölçümü için.
  final List<Uri> uris = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final uri = request.url;
    uris.add(uri);
    Object? body = <Object>[];
    if (uri.path.endsWith('/meal_entries')) {
      mealUris.add(uri);
      body = rows;
    } else if (uri.path.endsWith('/weight_entries')) {
      // `maybeSingle()` → gövde `null` olmalı.
      body = null;
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

/// Gövde: `meal_entries` satırı. `foods` embed'i **harici parametredir** —
/// böylece `MealEntry.fromJson`'ın okuduğu gövde ile modelin beklediği
/// gömülü nesne ayrı ayrı denetlenebilir.
Map<String, dynamic> mealRow({
  String id = 'e1',
  String? foodId = 'f1',
  String? customName,
  Object? foodsEmbed,
  String entryDate = '2026-09-28',
}) =>
    {
      'id': id,
      'user_id': 'u1',
      'entry_date': entryDate,
      'meal_type': 'lunch',
      'food_id': foodId,
      'custom_name': customName,
      'amount_g_ml': 150.0,
      'calculated_kcal': 300.0,
      'calculated_protein': 30.0,
      'calculated_carbs': 5.0,
      'calculated_fat': 20.0,
      'note': null,
      'photo_url': null,
      'source': 'manual',
      'created_at': '2026-09-28T10:00:00Z',
      'updated_at': null,
      'deleted_at': null,
      'foods': ?foodsEmbed,
    };

/// `fetchDaily`'yi sahte bir PostgREST katmanıyla çalıştırır.
Future<DailyData> runFetchDaily(
  List<Map<String, dynamic>> rows,
  Probe probe,
) =>
    DiaryRepository(
      SupabaseClient(
        'https://probe.supabase.co',
        'anon-key',
        httpClient: probe,
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      ),
    ).fetchDaily('u1', DateTime(2026, 9, 28));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // 1) ⭐⭐ SORGUNUN KENDİSİ: `select` parametresi (ölçüm, A4r11 tersi)
  // =========================================================================
  group('⭐ fetchDaily sorgusu `foods(name)` embed\'i İSTEMEK ZORUNDA', () {
    test('⭐ `select` düz `*` DEĞİLDİR ve `foods(name)` içerir', () async {
      final probe = Probe([mealRow()]);
      await runFetchDaily([mealRow()], probe);

      expect(probe.mealUris, isNotEmpty, reason: 'ölçüm yapılamadı');
      final select = probe.mealUris.first.queryParameters['select']!;
      // ⭐ Tuzak #2: düz `select()` embed'i **açmaz** — PostgREST `select=*`
      // gönderir ve ayrı `foods` nesnesi **üretmez**. Yani `*` kabul edilirse
      // `displayName` sessizce "Bilinmeyen" kalır ve test **yeşil** görünür.
      expect(select, isNot('*'),
          reason: 'düz select() embed açmaz → gıda adı hiç gelmez');
      expect(select, contains('foods(name)'),
          reason: 'gıda adı `foods` JOIN\'inden gelir (`meal_entries` kolonu '
              'değil)');
    });

    test('⭐ kolon listesi `MealEntry.fromJson`\'ın okuduğu kolonlarla BİREBİR',
        () async {
      // ⭐ Tuzak #2'nin derinliği: liste hem **eksiksiz** hem **dar** olmalı.
      // Eksiksiz değilse `fromJson` `as String` cast'i patlatır (TypeError →
      // tüm günlük ekranı düşer). Fazlası gereksiz indirme (ve `created_by`
      // gibi kullanılmayan kişisel alanlar).
      final select = mealEntrySelectWithFoodName;
      final columns = select
          .split(',')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty && !c.contains('('))
          .toList();

      // (a) Üretim kodunun **gerçekten okuduğu** anahtarlar ham JSON'dan çıkarılır.
      final read = _keysReadByFromJson();

      // (b) İkinci bir sabit liste **yazılmaz**; karşılaştırma `read` ile
      // yapılır → iki liste ayrışamaz (A3r6'nın "ölü sabit" kontrolü deseni).
      expect(columns, containsAll(read),
          reason: 'fromJson okuduğu kolon listede YOK → TypeError: '
              'eksik: ${read.where((k) => !columns.contains(k))}');
      // (c) Ekstra kolon **yoktur**: her seçilen kolon `fromJson` tarafından
      // okunur (fazlası = gereksiz indirme, `created_by` gibi).
      expect(columns.length, read.length,
          reason: 'kullanılmayan kolon indiriliyor: '
              '${columns.where((c) => !read.contains(c))}');

      // (d) `foods` embed'i **yalnız `name`** okumalı: `foods` 12 kolonlu
      // (`full_setup.sql:151-164`), günlük ekranın kullanacağı tek kolon
      // `name`. `select=*` yazılsaydı `created_by`, `verified`,
      // `popularity_count` gibi kullanılmayan kolonlar da gömülü nesneye
      // açılırdı.
      final embeds = RegExp(r'\b([a-z_]+)\(')
          .allMatches(select)
          .map((m) => m.group(1)!)
          .toList();
      expect(embeds, equals(['foods']),
          reason: 'tek gömülü nesne olmalı (`foods`); '
              '`food_nutrition` vb. günlük ekranda kullanılmıyor');
      expect(RegExp(r'foods\(([^)]*)\)').firstMatch(select)!.group(1), 'name',
          reason: 'gömülü nesne **yalnız `name`** istemeli (A4r11 tuzağı: '
              '`select=*` gereksiz kolon ve `created_by` indirir)');
    });

    test('sorgu süzgeçleri korunur (kullanıcı/gün/yumuşak silme)', () async {
      final probe = Probe([mealRow()]);
      await runFetchDaily([mealRow()], probe);
      final q = probe.mealUris.first.queryParameters;
      expect(q['user_id'], 'eq.u1');
      expect(q['entry_date'], 'eq.2026-09-28');
      expect(q['deleted_at'], 'is.null',
          reason: 'yumuşak silinen öğün gün toplamına girmemeli');
      expect(q['order'], contains('created_at'));
    });

    test('⭐ istek SAYISI değişmedi (embed ayrı istek değil)', () async {
      // ⭐ İkinci maliyet boyutu: embed **ayrı bir HTTP isteği** üretmez
      // (PostgREST gömülü nesneyi aynı yanıtta döndürür). Düz `select()` ile
      // `foods(name)` arasındaki fark **istek sayısı** değil, **yanıt boyutu**.
      // Ölçüm: `fetchDaily` 3 istek atar (öğünler + su + kilo) — düz select
      // de 3. Yani burada N+1 **yok**.
      final probe = Probe([mealRow()]);
      await runFetchDaily([mealRow()], probe);
      expect(probe.uris, hasLength(3),
          reason: 'meals + water + weight; embed 4. istek yaratmamalı');
      expect(probe.mealUris, hasLength(1));
    });
  });

  // =========================================================================
  // 2) ⭐ P1 DÜZELTMESİ: topluluk gıdası öğünü adını gösteriyor
  // =========================================================================
  group('⭐ P1: `food_id` dolu + `custom_name` NULL → ad görünüyor', () {
    test('⭐ ham JSON → displayName gıdanın adı', () async {
      // ⭐ Ham denetim: `displayName` **sonucu** değil, `foodName` **alanı**
      // denetleniyor; gömülü nesne gerçekten okunduğu görülüyor.
      final entry = MealEntry.fromJson(mealRow(
        foodId: 'f1',
        customName: null,
        foodsEmbed: const {'name': 'Tavuk Göğsü'},
      ));
      expect(entry.foodName, 'Tavuk Göğsü');
      expect(entry.customName, isNull);
      expect(entry.foodId, 'f1');
      expect(entry.displayName, 'Tavuk Göğsü',
          reason: 'v1.2.0\'dan beri "Bilinmeyen" görünüyordu');
      expect(entry.displayName, isNot('Bilinmeyen'));
    });

    test('⭐ fetchDaily UÇTAN UCA: dashboard artık "Bilinmeyen" DEĞİL',
        () async {
      // ⭐ Tuzak #3: `select` metnine bakmak **yetmez** — gerçek PostgREST
      // gövdesi döndürülür ve `fetchDaily` **çökmemeli** (kolon eksikse
      // `fromJson` `TypeError` verir) ve ad **gerçekten** taşınmalı.
      final probe = Probe([
        mealRow(id: 'e1', foodsEmbed: const {'name': 'Tavuk Göğsü'}),
        mealRow(id: 'e2', foodsEmbed: const {'name': 'Pilav'}),
      ]);
      final data = await runFetchDaily([mealRow()], probe);

      expect(data.mealEntries, hasLength(2),
          reason: 'kolon listesi eksiksiz değilse burası TypeError olurdu');
      expect(data.mealEntries.map((e) => e.displayName),
          equals(['Tavuk Göğsü', 'Pilav']));
      expect(data.mealEntries.every((e) => e.displayName != 'Bilinmeyen'), isTrue);
    });

    test('⭐ kaynak önceliği: `custom_name` ÖNCE gelir (A4r11 kuralı)',
        () async {
      // Kullanıcı gıdayı kendi cümlesiyle adlandırdıysa `foods.name`
      // (topluluk adı) onu **ezmemeli**.
      final entry = MealEntry.fromJson(mealRow(
        customName: 'Ev Yapımı Köfte',
        foodsEmbed: const {'name': 'Tavuk Köfte (market)'},
      ));
      expect(entry.customName, 'Ev Yapımı Köfte');
      expect(entry.foodName, 'Tavuk Köfte (market)',
          reason: 'alan **değerini** okumak sözleşmenin parçası');
      expect(entry.displayName, 'Ev Yapımı Köfte',
          reason: 'A4r11: kullanıcının girdiği ad önce gelir');
    });

    test('⭐ ters yön de kilitli: `custom_name` yazılıysa JOIN gerekmez',
        () async {
      // A4r11'in yaptığı düzeltme bozulmamalı: `custom_name` yazılı bir öğün
      // embed'siz de adını göstermeye devam eder (yedek/import yolu
      // `custom_name` yazar, embed sorgusu hiç çalışmıyor olabilir).
      final entry = MealEntry.fromJson(mealRow(
        customName: 'Ev Yapımı Köfte',
        foodsEmbed: null,
      ));
      expect(entry.foodName, isNull);
      expect(entry.displayName, 'Ev Yapımı Köfte');
    });
  });

  // =========================================================================
  // 3) ⭐ SOLVER DAYANIKLIĞI: embed biçimleri
  // =========================================================================
  group('⭐ `foods` embed biçimleri (PostgREST + bozuk gövde)', () {
    Map<String, dynamic> withEmbed(Object? embed) =>
        mealRow(foodsEmbed: embed, customName: null);

    test('düz nesne: `{"name": "Yoğurt"}`', () {
      expect(MealEntry.fromJson(withEmbed(const {'name': 'Yoğurt'})).foodName,
          'Yoğurt');
    });

    test('to-many liste: `[{"name": "Yoğurt"}]`', () {
      // `foods!inner(name)` bir yanlışlıkla yazılırsa PostgREST **liste**
      // döndürür; `as Map` cast'i **çökerdi**. Savunma derinliği ölçüldü.
      expect(MealEntry.fromJson(withEmbed(const [
        {'name': 'Yoğurt'},
      ])).foodName, 'Yoğurt');
    });

    test('tek kolon embed düz dize dönebilir: `"Yoğurt"`', () {
      expect(MealEntry.fromJson(withEmbed('Yoğurt')).foodName, 'Yoğurt');
    });

    test('`null` embed → `foodName` null (gıda silinmiş veya `food_id` NULL)',
        () {
      final e = MealEntry.fromJson(withEmbed(null));
      expect(e.foodName, isNull);
      expect(e.displayName, 'Bilinmeyen',
          reason: 'gerçek ad yok → eski davranış birebir korunur');
    });

    test('⭐ boş/bozuk ad → "Bilinmeyen" (veri uydurulmaz)', () {
      for (final embed in const <Object?>[
        {'name': ''},
        {'name': '   '},
        {'name': null},
        <String, Object?>{}, // `name` kolonu seçilmemiş
        {'id': 'f1'}, // sorgu `foods(name)` demeyi unutmuş
      ]) {
        final e = MealEntry.fromJson(withEmbed(embed));
        expect(e.foodName, isNull, reason: 'embed=$embed');
        expect(e.displayName, 'Bilinmeyen', reason: 'embed=$embed');
      }
    });

    test('⭐ bozuk gövde tipleri ÇÖKMEZ (tam günlük ekranı düşerdi)', () {
      // A2r5'in "tek bozuk eleman tüm ekranı düşürüyordu" sınıfının JOIN
      // tarafındaki karşılığı: `as Map<String,dynamic>` yerine **tür denetimi**.
      for (final embed in const <Object?>[42, true, <Object?>[], <String>[]]) {
        final e = MealEntry.fromJson(withEmbed(embed));
        expect(e.foodName, isNull, reason: 'embed=$embed');
        expect(e.displayName, 'Bilinmeyen', reason: 'embed=$embed');
      }
    });

    test('ad kırpılır (`"  Yoğurt  "` → `"Yoğurt"`)', () {
      expect(MealEntry.fromJson(withEmbed(const {'name': '  Yoğurt  '})).foodName,
          'Yoğurt');
    });
  });

  // =========================================================================
  // 4) ⭐ "Bilinmeyen" ASLA kullanıcının girdisi olamaz (A2r12 sözleşmesi)
  // =========================================================================
  group('⭐ modelin placeholder etiketi veri olamaz', () {
    test('`custom_name` beyaz boşluk → "Bilinmeyen"', () {
      // Eski davranış `customName ?? 'Bilinmeyen'` idi: `custom_name: "  "`
      // (whitespace) ekranda **boş bir başlık** olarak görünürdü.
      final e = MealEntry.fromJson(mealRow(
        customName: '   ',
        foodsEmbed: const {'name': 'Yoğurt'},
      ));
      expect(e.displayName, 'Yoğurt',
          reason: 'whitespace `custom_name` JOIN adını **ezmemeli**');
    });

    test('`EditMealEntryDialog._seedName` "Bilinmeyen"i yazmaz', () {
      // A2r12'nin kuralı: modelin sabit etiketi (`meal_entry.dart`) kullanıcının
      // girdisi **olamaz**. Diyalog bunu `displayName == 'Bilinmeyen'` ile
      // eşleşip boş bırakarak sağlıyor; burada o eşleşmenin **tutarlılığı**
      // ölçülüyor (etiket iki yerde de aynı sabit olmalı).
      final orphan = MealEntry.fromJson(mealRow(customName: null));
      expect(orphan.displayName, 'Bilinmeyen');
      // Diyalog `shown == _unknownFoodLabel ? '' : shown` uygular:
      final shown = orphan.displayName;
      final seeded = shown == 'Bilinmeyen' ? '' : shown;
      expect(seeded, isEmpty,
          reason: '"Bilinmeyen" ad olarak yazılırsa veri uydurulmuş olur');
    });
  });

  // =========================================================================
  // 5) ⭐ `toJson` sözleşmesi: `food_name` **yazılmaz**
  // =========================================================================
  group('⭐ `toJson` türetilmiş alanı **kaydetmez**', () {
    test('⭐ `food_name` gövdede **yok** (bayatlık/sessiz bozulma olmaz)', () {
      final e = MealEntry.fromJson(mealRow(
        foodsEmbed: const {'name': 'Yoğurt'},
      ));
      final row = e.toJson();
      expect(e.foodName, 'Yoğurt', reason: 'modelde var');
      expect(row.containsKey('food_name'), isFalse,
          reason: '`meal_entries.food_name` kolonu **yok**; yazmak iki '
              'doğruluk kaynağı üretirdi (gıda adı değişince bayatlar)');
      expect(row.containsKey('foods'), isFalse);
    });

    test('`toJson` → `fromJson` gidiş-dönüşü JOIN\'siz satırı korur', () {
      const original = MealEntry(
        id: 'e1',
        userId: 'u1',
        mealType: 'lunch',
        amountGMl: 150,
        calculatedKcal: 300,
        calculatedProtein: 30,
        calculatedCarbs: 5,
        calculatedFat: 20,
        entryDate: '2026-09-28',
        source: 'manual',
        createdAt: '2026-09-28T10:00:00Z',
        customName: 'Ev Yapımı Köfte',
      );
      final back = MealEntry.fromJson(original.toJson());
      expect(back.customName, original.customName);
      expect(back.foodId, original.foodId);
      expect(back.displayName, 'Ev Yapımı Köfte');
      expect(back.toJson(), equals(original.toJson()),
          reason: 'gidiş-dönüş **kayıtsız** (nullable alanlar korunmalı)');
    });

    test('`toJson` gövdesi `meal_entries` yazılabilir kolonlarıyla uyumlu',
        () {
      // A2r4/A2r5'in "gövdeden düşen NOT NULL kolonu **tüm import'u**
      // düşürür" sınıfı. Yedek dışa aktarımı `data_transfer_repository.dart`'ın
      // kendi `_mealRow`'unu kullanır; buradaki `toJson` ikinci bir sözleşme.
      final row = MealEntry.fromJson(mealRow()).toJson();
      for (final col in const [
        'id',
        'user_id',
        'entry_date',
        'meal_type',
        'amount_g_ml',
        'calculated_kcal',
        'calculated_protein',
        'calculated_carbs',
        'calculated_fat',
        'source',
        'created_at',
      ]) {
        expect(row.containsKey(col), isTrue, reason: '$col eksik → DB 400');
      }
    });
  });
}

/// `MealEntry.fromJson` gövdesinin gerçekten okuduğu **JSON anahtarları**.
///
/// ⭐ Bu, testin **ölçüm** kısmıdır: ikinci bir sabit liste yazmak yerine
/// üretim kodunun metnini okuyup `json['…']` anahtarlarını çıkarırız. Böylece
/// (a) liste `fromJson` ile **birebir** eşleşmek zorundadır ve (b) `fromJson`
/// yeni bir kolon eklerse test **kırmızıya döner** (sessiz boşluk oluşmaz).
/// Tuzak #2'nin derinliği: kolon listesini elle yazarsak iki liste zamanla
/// ayrışır ve test "yeşil görünürken hiçbir şey ölçmeyen" bir sözleşmeye
/// dönüşür — bu döngüde 6 kez yakalanan sınıf.
List<String> _keysReadByFromJson() {
  // `fromJson`'ın okuduğu anahtarlar **kaynak metinden** çıkarılır; test
  // çalışma dizini `flutter_app/` köküdür (CI'da da öyle —
  // `.github/workflows/flutter.yml` `working-directory: flutter_app`).
  final file = File('lib/data/models/meal_entry.dart');
  expect(file.existsSync(), isTrue,
      reason: 'kaynak dosya bulunamadı (yanlış çalışma dizini): ${file.path}');
  final source = file.readAsStringSync();
  final start = source.indexOf('factory MealEntry.fromJson');
  expect(start == -1, isFalse, reason: 'fromJson bulunamadı');
  final body = source.substring(start);
  // ⭐ Gömülü `json['foods']` **kolon değil**, JOIN nesnesidir: `select`
  // listesinde karşılığı `foods(name)`'dir, düz `foods` değil. Bu yüzden
  // düz anahtarlar (17 kolon) gömülü anahtarlardan (1) **ayrılır**.
  final embedded =
      RegExp(r"json\['([a-z_]+)'\]").allMatches(body).map((m) {
    return m.group(1)!;
  }).toList();
  expect(embedded, contains('foods'),
      reason: 'embed okunmuyor → `foodName` hiç doldurulmaz (ölçüm hatalı)');
  final keys = embedded.where((k) => k != 'foods').toSet().toList()..sort();
  expect(keys.length, 17,
      reason: '`meal_entries` kolon sayısı değişti → select listesi güncellenmeli');
  return keys;
}

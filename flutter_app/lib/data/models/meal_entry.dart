import 'package:json_annotation/json_annotation.dart';

/// `meal_entries` tablosu — web `useDailyData.MealEntry` karşılığı.
///
/// `foodId` null ise kullanıcının manuel/özel girdisidir (`customName`).
/// Besin değerleri giriş anında `calculated_*` alanlarına yazılır
/// (amount değişse bile web'de de böyle saklanır).
///
/// ## ⭐ `fromJson`/`toJson` **elle** yazıldı (A2r13, Tur 13)
///
/// `json_serializable` üreticisi **kaldırıldı** (`meal_entry.g.dart` silindi).
/// Sebep: `foodName` bir JOIN kolonu (`{"name": …}`) ve satırın JSON anahtarı
/// değil → generatör bunu üretemez. `Profile` (`profile.dart`, A2r5) aynı
/// sebeple aynı yolu izledi; **kanıtlanmış öncü**, deneme-değil.
class MealEntry {
  const MealEntry({
    required this.id,
    required this.userId,
    required this.mealType,
    required this.amountGMl,
    required this.calculatedKcal,
    required this.calculatedProtein,
    required this.calculatedCarbs,
    required this.calculatedFat,
    required this.entryDate,
    required this.source,
    required this.createdAt,
    this.foodId,
    this.customName,
    this.note,
    this.photoUrl,
    this.updatedAt,
    this.deletedAt,
    this.foodName,
  });

  final String id;

  @JsonKey(name: 'user_id')
  final String userId;

  @JsonKey(name: 'food_id')
  final String? foodId;

  @JsonKey(name: 'custom_name')
  final String? customName;

  /// `meal_type` enum: breakfast | lunch | dinner | snack
  @JsonKey(name: 'meal_type')
  final String mealType;

  @JsonKey(name: 'amount_g_ml')
  final double amountGMl;

  @JsonKey(name: 'calculated_kcal')
  final double calculatedKcal;

  @JsonKey(name: 'calculated_protein')
  final double calculatedProtein;

  @JsonKey(name: 'calculated_carbs')
  final double calculatedCarbs;

  @JsonKey(name: 'calculated_fat')
  final double calculatedFat;

  /// `yyyy-MM-dd` formatında gün.
  @JsonKey(name: 'entry_date')
  final String entryDate;

  final String? note;

  @JsonKey(name: 'photo_url')
  final String? photoUrl;

  /// `food_source` enum: photo | text | manual
  final String source;

  @JsonKey(name: 'created_at')
  final String createdAt;

  @JsonKey(name: 'updated_at')
  final String? updatedAt;

  @JsonKey(name: 'deleted_at')
  final String? deletedAt;

  /// ⭐ `foods.name` — JOIN'den gelen **türetilmiş** alan (A2r13, Tur 13).
  ///
  /// ## Sorun neydi?
  ///
  /// `DiaryRepository.fetchDaily` `foods` JOIN'i **yapmıyordu** ve
  /// `displayName` yalnızca `custom_name` okuyordu. Sonuç: **v1.2.0'dan
  /// beri** `food_id` dolu ama `custom_name` NULL olan **her** öğün
  /// dashboard'da "Bilinmeyen" görünüyordu. `add_from_food_dialog`
  /// (`add_from_food_dialog.dart:96-109`) `custom_name`'i yalnızca
  /// `isCustom || canDelete` için yazdığı için **topluluk/seed gıdasından
  /// eklenen her öğün** bu duruma düşüyordu. Ölçüm:
  /// `fetchdaily_no_foods_join_measurement_a4r11_test.dart`
  /// (`select=%2A`, `foods(` embed'i **yok**) — A4r11'in kendi probu).
  ///
  /// ## Alan neden **kaydedilmiyor** (`toJson`'a yazılmıyor)?
  ///
  /// `meal_entries` tablosunda `food_name` **kolonu yok**. `food_id` FK'si
  /// zaten adı tutar; gıdanın adı tek doğruluk kaynağı `foods.name`
  /// kolonudur. Yazmak iki doğruluk kaynağı üretirdi (gıda yeniden adlandırılır
  /// / silinir → `food_name` bayatlar) ve A2r4'ün "**sessiz veri bozulması**"
  /// sınıfına girerdi. `DataTransferRepository` yedeği de `food_id` üzerinden
  /// kurar (`data_transfer_repository.dart:1304-1309`), yani `food_name`
  /// yedeğe girerse aynı bayatlık oraya da yayılır.
  ///
  /// ## Neden `fromJson` elle yazıldı?
  ///
  /// Aynı gerekçe `Profile`'ta (`profile.dart:130-168`): `json_serializable`
  /// bu alan için **JSON anahtarı** üretemez, çünkü alan bir JOIN nesnesinin
  /// (`{"name": "Yoğurt"}`) içinden okunuyor. Bu yüzden `fromJson` elle
  /// yazıldı; `toJson` da alanı **dikkate almadan** bırakıyor.
  ///
  /// ## `foods` embed'i **LEFT JOIN**'dir — iki biçim
  ///
  /// PostgREST `foods(name)` embed'i **`foods` kaydı yoksa `null` verir**
  /// (nullable FK). İki ayrı durum ayrıştırılıyor:
  ///
  /// | `foods` | anlamı | `displayName` |
  /// |---|---|---|
  /// | `null`   | `food_id` NULL **veya** gıda silinmiş | `customName` → yoksa "Bilinmeyen" |
  /// | `{name}` | gıda hâlâ duruyor | `customName` → yoksa **`foods.name`** |
  ///
  /// ⭐ Boş **string** (`{"name": ""}`) yine de `foods`'ın **var olduğu**
  /// anlamına gelir ama kullanılabilir bir ad değildir → `displayName` "Bilinmeyen"
  /// olur. `food_id` **dolu** ama `customs` embed'i **null** ise eski
  /// davranış (custom_name → "Bilinmeyen") **birebir** korunur, yani
  /// embed'i olmayan eski bir istemci/JSON için geriye dönük uyum bozulmaz.
  final String? foodName;

  factory MealEntry.fromJson(Map<String, dynamic> json) => MealEntry(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        mealType: json['meal_type'] as String,
        amountGMl: (json['amount_g_ml'] as num).toDouble(),
        calculatedKcal: (json['calculated_kcal'] as num).toDouble(),
        calculatedProtein: (json['calculated_protein'] as num).toDouble(),
        calculatedCarbs: (json['calculated_carbs'] as num).toDouble(),
        calculatedFat: (json['calculated_fat'] as num).toDouble(),
        entryDate: json['entry_date'] as String,
        source: json['source'] as String,
        createdAt: json['created_at'] as String,
        foodId: json['food_id'] as String?,
        customName: json['custom_name'] as String?,
        note: json['note'] as String?,
        photoUrl: json['photo_url'] as String?,
        updatedAt: json['updated_at'] as String?,
        deletedAt: json['deleted_at'] as String?,
        foodName: _readEmbeddedFoodName(json['foods']),
      );

  /// `foods(name)` embed'inden gıda adı.
  ///
  /// ## Neden savunma katmanı bu kadar geniş?
  ///
  /// Döndürülebilecek **dört** ayrı biçim ölçüldü; hepsi `MealEntry`in
  /// güvenli varsayılanına düşmeli (A5r10/A2r5'in `1` → sayaç değeri sınıfı:
  /// ham/bozuk elemanla tüm günlük ekranı düşürmemek):
  ///
  /// | JSON                              | sonuç  | neden |
  /// |---|---|---|
  /// | `null`                            | `null` | LEFT JOIN boş (`food_id` NULL veya gıda silinmiş) |
  /// | `{"name": "Yoğurt"}`              | `"Yoğurt"` | normal |
  /// | `[{"name": "Yoğurt"}]`            | `"Yoğurt"` | PostgREST to-many gömebilir; `food_id` tekil FK ama savunma |
  /// | `"Yoğurt"` (düz dize)             | `"Yoğurt"` | tek kolon embed'i düz dize dönebilir |
  /// | `{"name": ""}` / `{"name": null}` | `null` | kayıt var ama ad yok → "Bilinmeyen" |
  /// | `{"id": ...}` (ad kolonu seçilmemiş) | `null` | sorgu `foods(name)` demeyi unutursa |
  /// | `42`, `true`, `[]`                | `null` | bozuk gövde → çökme yok |
  static String? _readEmbeddedFoodName(Object? embedded) {
    if (embedded == null) return null;
    if (embedded is String) return _nonBlank(embedded);
    if (embedded is List) {
      // PostgREST to-many (`foods!inner(name)`) liste döndürebilir. `food_id`
      // tekil FK olduğu için normalde tek elemanlıdır; ilk **adı olan** eleman
      // kullanılır (liste sırası garantili değil, `id` sırası da değil).
      for (final element in embedded) {
        final name = _readEmbeddedFoodName(element);
        if (name != null) return name;
      }
      return null;
    }
    if (embedded is Map) {
      // Sürüme göre `Map<String, dynamic>` **veya** `Map<dynamic, dynamic>`
      // olabilir; `as Map<String, dynamic>` bu yüzden kullanılmaz.
      final name = embedded['name'];
      if (name is String) return _nonBlank(name);
      return null;
    }
    return null;
  }

  static String? _nonBlank(String v) {
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// ## Neden `fromJson` **elle** yazıldı?
  ///
  /// Aynı gerekçe `Profile`'ta (`profile.dart`, A2r5, Tur 5): `json_serializable`
  /// bu alan için **JSON anahtarı** üretemez, çünkü alan bir JOIN nesnesinin
  /// (`{"name": "Yoğurt"}`) içinden okunuyor, satırın kendi kolonu değil.
  /// `Profile` da `profile.g.dart` dosyasını **sildi** ve `fromJson`/`toJson`'u
  /// elle yazdı; burada da **birebir** aynı yol izlendi:
  ///
  /// * `part 'meal_entry.g.dart'` satırı ve dosya **kaldırıldı**,
  /// * `build_runner`'a bağımlılık **biter** (`profile.g.dart` zaten yok,
  ///   yani bu model artık bu depoda üretilen `.g.dart` dosyalarından
  ///   **tek istisna** değildir),
  /// * `toJson` elle yazıldı ve `foodName` alanını **bilerek dışladı**
  ///   (gövde = `meal_entries`'in yazılabilir kolonları; JOIN kolonu değil).
  ///
  /// ⭐ `toJson`'un **sözleşmesi** `DataTransferRepository` ile uyumludur:
  /// yedek dışa aktarımı `toJson`'u değil, `data_transfer_repository.dart`'ın
  /// **kendi** `_mealRow`'unu kullanır (`:1152`); buradaki `toJson` ise
  /// `DataTransferRepository`'nin yazdığı kolon kümesiyle aynı 16 kolonu
  /// (`food_name` hariç) üretir.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'user_id': userId,
        'food_id': foodId,
        'custom_name': customName,
        'meal_type': mealType,
        'amount_g_ml': amountGMl,
        'calculated_kcal': calculatedKcal,
        'calculated_protein': calculatedProtein,
        'calculated_carbs': calculatedCarbs,
        'calculated_fat': calculatedFat,
        'entry_date': entryDate,
        'note': note,
        'photo_url': photoUrl,
        'source': source,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  /// Görünen ad — **kaynak önceliği** (A2r13, Tur 13).
  ///
  /// 1. `customName` — kullanıcının **kendi girdiği** ad. Her zaman önce
  ///    gelir: kullanıcı gıdayı "Ev Yapımı Köfte" diye adlandırdıysa, arayüz
  ///    bugün ne yediğini **kendi cümlesiyle** hatırlamak ister ve `foods.name`
  ///    (topluluk adı) onu ezmelidir. A4r11'in ölçtüğü kural budur.
  /// 2. `foodName` — `foods` tablosundaki **kayıtlı** ad (topluluk/seed gıdası,
  ///    ya da kullanıcının kendi eklediği gıda). Bu dal **v1.2.0'dan beri**
  ///    hiç çalışmıyordu (embed yoktu) → dashboard'da "Bilinmeyen".
  /// 3. `"Bilinmeyen"` — gerçekten hiç ad yok. Bu bir **yer tutucu** etiketidir:
  ///    `EditMealEntryDialog._seedName` bu değeri ad olarak **yazmaz**
  ///    (`edit_meal_entry_dialog.dart:150`), yani modelin sabit metni
  ///    kullanıcının girdisi olamaz.
  String get displayName {
    final custom = customName;
    if (custom != null) {
      final trimmed = custom.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    final food = foodName;
    if (food != null && food.trim().isNotEmpty) return food;
    return 'Bilinmeyen';
  }
}

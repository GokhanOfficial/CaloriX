/// Tartılma sıklığı girişinin **arayüz tarafı** sözleşmesi (A4r10, Tur 11).
///
/// ## Gerçek DB CHECK sınırları (tahmin değil, şemadan okundu)
///
/// `supabase/migrations/20260928400000_data_integrity_check_constraints.sql:227-228`
/// ve `supabase/full_setup.sql:1015-1016` — **aynı ifade**, iki dosyada da:
///
/// ```sql
/// ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_weigh_in_frequency_days_range;
/// ALTER TABLE public.profiles
///   ADD CONSTRAINT profiles_weigh_in_frequency_days_range
///   CHECK (weigh_in_frequency_days IS NULL OR weigh_in_frequency_days BETWEEN 1 AND 365);
/// ```
///
/// Yani **gerçek kabul aralığı `1..365`** (`NULL` da serbest). A2r9'ın veri
/// katmanındaki `ProfileRepository.fieldRanges['weigh_in_frequency_days']`
/// **aynı** değerleri taşıyor (`(min: 1, max: 365)`); bu dosya o sözleşmenin
/// **metin ayrıştırma** kısmını (arayüze özgü) tamamlar.
///
/// ## Neden arayüz katmanında ayrıca doğrulama? (veri katmanı yetmiyor)
///
/// `ProfileRepository.validateUpdates` değeri **reddedip `ProfileFieldRangeError`
/// fırlatıyor**; çağıran ekran `catch (_)` ile genel bir "Kaydedilemedi"
/// mesajı gösteriyor. Bu, düzeltilmiş hâliyle **veri kaybı değil** ama:
///
/// 1. Kullanıcı `0` yazıp "Kaydet"e bastığında profil + **sunucu bildirim
///    tercihleri** kaydedilmiyor (tek `_save` iki yazma yolunu da kapsıyor,
///    `notifications_dialog.dart:175-207`) → kullanıcı "hiçbir şeyim
///    kaydedilmedi" diye düşünür, oysa hata yalnızca tek alandan geliyor.
/// 2. Hata mesajı **hangi alanın** neden reddedildiğini söylemez.
/// 3. `FilteringTextInputFormatter.digitsOnly` negatif değeri (`-5`) zaten
///    engelliyordu ama **`0`'ı engellemiyordu** — ve `0`, CHECK'in alt
///    sınırıdır. Üstelik alan `kaydedilebilir` olduğu için hata
///    **kullanıcıdan önce** (`_save` içinde) patlıyordu.
///
/// Bu yüzden giriş **kendi sınırını** taşır: `validator` anında kırmızı
/// metin gösterir, "Kaydet" **pasif** olur, hata hiçbir zaman sunucuya
/// ulaşmaz.
///
/// ## Neden `clamp` değil `validator`?
///
/// `clamp` sessiz veri bozulmasıdır: kullanıcı `0` yazdı, kayıt `1` olarak
/// saklandı ve kullanıcı **kendi girdisini göremiyor**. A2r9'ın
/// `ProfileRepository` yorumundaki gerekçe aynıdır: kısıtı öğrenmek,
/// sessizce düzeltilmiş değeri görmekten iyidir.
library;

/// `weigh_in_frequency_days` için **gerçek** alt sınır (`BETWEEN 1 AND 365`).
const int kWeighInMinDays = 1;

/// `weigh_in_frequency_days` için **gerçek** üst sınır.
const int kWeighInMaxDays = 365;

/// `profiles.weigh_in_frequency_days` kolonunun `DEFAULT 7` değeri
/// (`full_setup.sql:128`) — `NULL` profil için kullanılan varsayılan.
const int kWeighInDefaultDays = 7;

/// Metinden tartılma sıklığı ayrıştırır: `1..365` aralığında mı?
///
/// ## Neden `int.tryParse` tek başına yetmez?
///
/// `int.tryParse('0')` `0` döner ve `?? 7` **devreye girmez** — `??` yalnız
/// `null` üstüne düşer. A1r8'in migration yorumu (`:151-159`) bu yüzden `0`'ı
/// "deneyimsel olarak güvenli" saydı ama negatif değeri `check-reminders`'ta
/// **her koşuda** tetikleyen durumu yarattı. CHECK `1..365` ikisini de
/// kapatıyor; bu fonksiyon istemci tarafında aynı sözleşmeyi uygular.
///
/// ## Dönüş değeri
///
/// - `[1..365]` içindeki bir tam sayı → o değer.
/// - **Boş metin** → `null` (kullanıcı henüz bir şey yazmadı → kaydetmeye
///   izin verilir, DB `DEFAULT 7` geçerli ve aralık içindedir).
/// - Harf, ondalık, `+7`, `0x10`, `1e3`, `-5`, `0`, `366` → `null`
///   (**geçersiz**).
///
/// Aralık dışı değer `null` döner; çağıran `null`ı "boş" ile
/// "geçersiz" arasında ayırmak isterse [isBlankWeighInInput] kullanır.
int? parseWeighInFrequencyDays(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  // ⚠️ **Ölçülen tuzak:** Dart `int.tryParse('0x10')` → **16** döner
  // ( hexadecimal ), `int.tryParse('+7')` → **7** döner. Yani `tryParse`
  // tek başına "kullanıcı rakam yazdı" anlamına **gelmez**; bir yol
  // (yapıştırma, `TextFormField` otomatik doldurma, `enterText` testi)
  // `digitsOnly` formatters'ı atlayabilir ve kullanıcı **16 gün** yazdığını
  // sanarken o sayı yazılır. Bu yüzden biçim de doğrulanır.
  if (!_digitsOnly.hasMatch(text)) return null;
  final value = int.tryParse(text);
  if (value == null) return null;
  if (value < kWeighInMinDays || value > kWeighInMaxDays) return null;
  return value;
}

/// `weigh_in_frequency_days` alanının kabul ettiği tek biçim: **yalnız rakam**.
///
/// `FilteringTextInputFormatter.digitsOnly` ile aynı kural (arayüz aynı
/// zamanda koruyor; bu ikinci katman formatters atlanırsa işe yarar).
final RegExp _digitsOnly = RegExp(r'^\d+$');

/// Giriş **boş mu** (`null` yazılacak mı)?
///
/// `parseWeighInFrequencyDays` boş metni de `null` döndürür; "Kaydet"
/// düğmesinin **geçersiz** metni engellemesi ama **boş** alanı engelle
/// memesi için bu ayrım gerekir (boş alan `DEFAULT 7` demektir, geçersiz
/// metin hata demektir).
bool isBlankWeighInInput(String raw) => raw.trim().isEmpty;

/// Giriş geçerli mi? — **boş** da geçerli sayılır (DB `DEFAULT 7`).
///
/// Bu, "Kaydet" düğmesinin `onPressed` kapısıdır: `false` ise düğme
/// **pasif** olur ve `ProfileRepository.validateUpdates`'in (A2r9)
/// fırlatacağı `ProfileFieldRangeError`'a **hiç** varılmaz — yani profil
/// **ve** sunucu bildirim tercihleri birlikte kurtulur.
bool isValidWeighInInput(String? raw) =>
    isBlankWeighInInput(raw ?? '') || parseWeighInFrequencyDays(raw!) != null;

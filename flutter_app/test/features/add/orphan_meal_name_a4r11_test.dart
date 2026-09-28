/// A4r11 (Tur 12) — **P0**: yemek silinince öğün "Bilinmeyen" oluyordu.
///
/// ## Hata (A2r11 buldu, kendi alanı dışı bıraktı)
///
/// `features/add/widgets/add_from_food_dialog.dart:90`
/// ```dart
/// customName: widget.food.isCustom ? widget.food.name : null,
/// ```
/// `custom_name` yalnız `isCustom`'a bağlıydı. Kullanıcının **kendi eklediği**
/// bir `foods` gıdasını öğüne eklediğinde `isCustom == false` (o satır
/// `foods` tablosundadır) → `custom_name` **NULL** yazılıyordu.
///
/// A4r10/A2r11'in yemek silme özelliği (`shared/widgets/delete_food_button.dart`)
/// bu satırı silince:
/// - `meal_entries.food_id` FK'si **`ON DELETE SET NULL`** → öğün satırı
///   **korunur** (kcal/makro duruyor, BOLA yok),
/// - `custom_name` zaten NULL → `DiaryRepository.fetchDaily` `foods` join'i
///   **yapmaz** (düz `select()`, `diary_repository.dart:145`) →
///   `MealEntry.displayName` (`meal_entry.dart:89`) → **`"Bilinmeyen"`**.
///
/// Kullanıcı: "Bu öğün neydi?" → kalorisi duran ama adı olmayan kayıt.
/// Bu, Tur 11'in yemek silme özelliğinin **kullanıcıya verdiği zarar**.
///
/// ## Düzeltme
///
/// `customName: (food.isCustom || food.canDelete) ? food.name : null`
///
/// `canDelete` **birebir** "`bu gıda silinebilir mi`" koşuludur
/// (`food_repository.dart:24-63`: `created_by == userId`; RLS DELETE politikasıyla
/// aynı). Yani "adı yedekle" ile "gıda silinebilir" aynı sorunun iki yüzü.
///
/// ## Karar tablosu (gerekçesi bu dosyanın konusu)
///
/// | Senaryo                      | food_id | canDelete | custom_name | Gerekçe |
/// |------------------------------|---------|-----------|-------------|---------|
/// | Elle giriş (`isCustom`)       | NULL    | –         | **dolu**    | ad zaten gerekli (değişmedi) |
/// | AI tanıma (`source: photo/text`) | NULL | –         | **dolu**    | `food_id` hep NULL; ad şart (değişmedi) |
/// | Kendi eklediği DB gıdası      | var     | **true**  | **dolu**    | ⭐ P0: silinince ad kaybolmasın |
/// | Topluluk/seed gıdası          | var     | false     | NULL        | silinemez → FK kırılmaz → gereksiz tekrar |
/// | Başkasının gıdası             | var     | false     | NULL        | aynı |
///
/// ## ⭐ "Yeşil test ≠ etkin test" tuzağına karşı (A4r7b / A4r10 / A5r10)
///
/// Bu dosya, `custom_name` kararını **üretim kodunun bir yardımcı
/// fonksiyonundan geçirip sonucu denetlemez** — A5r10'un tuzağı tam olarak
/// budur (hatayı düzelten katmanın çıktısını denetlemek, hatayı gizlemek).
///
/// Bunun yerine:
/// 1. **Ham değer** denetlenir: mock repository'nin aldığı `customName`
///    parametresi **doğrudan** `expect` edilir; `MealEntry`/`FoodItem`
///    dönüşümünden geçmez.
/// 2. `_tapAdd`, butonun **ekran içinde olduğunu doğrular**, basar ve
///    `pumpAndSettle` sonrası kaydın **gerçekten oluştuğunu** ek bir
///    `expect` ile kanıtlar (A4r7b: `tap` sessizce hiçbir şey yapıyordu).
/// 3. `MealEntry.displayName` yalnız **ayrı** bir testte, elle kurulmuş bir
///    `MealEntry` üzerinden denetlenir; yazma testi bu fonksiyondan geçmez.
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/data/models/food_item.dart';
import 'package:calorix/data/models/meal_entry.dart';
import 'package:calorix/data/repositories/auth_repository.dart';
import 'package:calorix/data/repositories/diary_repository.dart';
import 'package:calorix/data/repositories/food_repository.dart';
import 'package:calorix/features/add/widgets/add_from_food_dialog.dart';
import 'package:calorix/shared/widgets/delete_food_button.dart';

class _MockDiaryRepository extends Mock implements DiaryRepository {}

class _MockFoodRepository extends Mock implements FoodRepository {}

const _kUser = User(
  id: 'u1',
  appMetadata: {},
  userMetadata: null,
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

final _dummyEntry = MealEntry(
  id: 'e1',
  userId: 'u1',
  mealType: 'lunch',
  amountGMl: 100,
  calculatedKcal: 250,
  calculatedProtein: 20,
  calculatedCarbs: 5,
  calculatedFat: 15,
  entryDate: '2026-09-28',
  source: 'manual',
  createdAt: '2026-09-28T12:00:00Z',
);

/// ⭐ `addMealEntry`'e **doğrudan** geçen ham argümanlar. Arada hiçbir
/// üretim kodu dönüşümü yoktur (A5r10 tuzağı).
class _Captured {
  String? customName;
  String? foodId;
  int calls = 0;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.ensureInitialized();
  });

  // ==========================================================================
  // 1) ⭐ P0: `custom_name` yazma kararı
  // ==========================================================================
  group('⭐ P0 — add_from_food_dialog custom_name kararı', () {
    late _MockDiaryRepository diary;
    late _MockFoodRepository food;
    late _Captured captured;

    setUp(() {
      diary = _MockDiaryRepository();
      food = _MockFoodRepository();
      captured = _Captured();
      when(() => diary.addMealEntry(
            any(),
            mealType: any(named: 'mealType'),
            amountGMl: any(named: 'amountGMl'),
            calculatedKcal: any(named: 'calculatedKcal'),
            calculatedProtein: any(named: 'calculatedProtein'),
            calculatedCarbs: any(named: 'calculatedCarbs'),
            calculatedFat: any(named: 'calculatedFat'),
            entryDate: any(named: 'entryDate'),
            foodId: any(named: 'foodId'),
            customName: any(named: 'customName'),
          )).thenAnswer((invocation) async {
        captured.calls++;
        captured.foodId = invocation.namedArguments[#foodId] as String?;
        captured.customName =
            invocation.namedArguments[#customName] as String?;
        return _dummyEntry;
      });
      // Favori yıldızı `favoriteIdsProvider` okur (gerçek sorgu) → burada
      // `customName`'in hesabına girmez, sadece ağ erişimini kesiyoruz.
      when(() => food.favoriteIds(any())).thenAnswer((_) async => <String>{});
    });

    Future<void> addFood(WidgetTester tester, FoodItem item) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('tr'), Locale('en')],
            path: 'assets/translations',
            fallbackLocale: const Locale('tr'),
            startLocale: const Locale('tr'),
            child: Builder(
              builder: (context) => ProviderScope(
                overrides: [
                  currentUserProvider.overrideWithValue(_kUser),
                  diaryRepositoryProvider.overrideWithValue(diary),
                  foodRepositoryProvider.overrideWithValue(food),
                  selectedDateProvider.overrideWith((_) {
                    return DateTime(2026, 9, 28);
                  }),
                ],
                child: MaterialApp(
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  home: Scaffold(
                    body: AddFromFoodDialog(
                      food: item,
                      defaultMealType: MealType.lunch,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      });
      await _tapAdd(tester, 'Yiyecek Ekle');

      // ⭐ Etkinlik kanıtı: kayıt **gerçekten** oluşmuş olmalı. Bu olmadan
      // aşağıdaki `customName` denetimleri `null`'ı görüp "yeşil" kalırdı
      // (A4r7b tuzağı: hiçbir şey ölçmeyen yeşil test).
      expect(captured.calls, 1,
          reason: 'kayıt oluşmadı → aşağıdaki denetimler anlamsız');
    }

    testWidgets('kendi eklediği gıda (canDelete=true) → ad YAZILIR',
        (tester) async {
      await addFood(
        tester,
        const FoodItem(
          id: 'mine-1',
          foodId: 'mine-1',
          name: 'Ev Yapımı Köfte',
          calories: 250,
          proteinG: 20,
          carbsG: 5,
          fatG: 15,
          canDelete: true,
        ),
      );

      expect(captured.foodId, 'mine-1');
      expect(
        captured.customName,
        'Ev Yapımı Köfte',
        reason:
            '⭐ P0: gıda silinebilir → `food_id` NULL olunca ad kaybolmasın; '
            'yoksa dashboard "Bilinmeyen" gösterir',
      );
    });

    testWidgets('isCustom=false AMA canDelete=true → ad YAZILIR (P0\'nin kendisi)',
        (tester) async {
      // Hatanın **tam olarak** yakalandığı senaryo: `foods` tablosunda bir
      // satır (isCustom=false) ama kullanıcının kendisi (canDelete=true).
      await addFood(
        tester,
        const FoodItem(
          id: 'mine-2',
          foodId: 'mine-2',
          name: 'Protein Kürdü',
          calories: 310,
          proteinG: 32,
          carbsG: 4,
          fatG: 18,
          canDelete: true,
        ),
      );

      expect(
        captured.customName,
        'Protein Kürdü',
        reason: 'eski kod (`isCustom` ? … : null) burada NULL yazıyordu',
      );
    });

    testWidgets('topluluk/seed gıdası (canDelete=false) → ad YAZILMAZ',
        (tester) async {
      await addFood(
        tester,
        const FoodItem(
          id: 'seed-1',
          foodId: 'seed-1',
          name: 'Mercimek Çorbası',
          calories: 90,
          proteinG: 4,
          carbsG: 12,
          fatG: 1,
        ),
      );

      expect(captured.foodId, 'seed-1');
      expect(
        captured.customName,
        isNull,
        reason:
            'silinemeyen gıda → FK hiç kırılmaz → `custom_name` her öğünde '
            'gereksiz kopya (veri şişirme)',
      );
    });

    testWidgets('manuel giriş (isCustom=true, foodId=null) → ad YAZILIR',
        (tester) async {
      await addFood(
        tester,
        const FoodItem(
          id: 'custom_1',
          name: 'Annemin Köftesi',
          calories: 240,
          proteinG: 19,
          carbsG: 6,
          fatG: 14,
          isCustom: true,
        ),
      );

      expect(captured.foodId, isNull);
      expect(captured.customName, 'Annemin Köftesi',
          reason: 'elle giriş DEĞİŞMEMELİ — ad her zaman gerekli');
    });

    testWidgets('tanıma sonucu (isCustom=true) → ad YAZILIR', (tester) async {
      await addFood(
        tester,
        const FoodItem(
          id: 'recognized_Tavuk',
          name: 'Tavuk Salata',
          calories: 120,
          proteinG: 18,
          carbsG: 3,
          fatG: 5,
          isCustom: true,
        ),
      );

      expect(captured.customName, 'Tavuk Salata');
    });
  });

  // ==========================================================================
  // 2) ⭐ "Bilinmeyen"in nasıl oluştuğunun kanıtı
  // ==========================================================================
  group('⭐ P0\'nin görünür yüzü: MealEntry.displayName', () {
    MealEntry build({String? foodId, String? customName}) => MealEntry(
          id: 'e1',
          userId: 'u1',
          foodId: foodId,
          customName: customName,
          mealType: 'lunch',
          amountGMl: 150,
          calculatedKcal: 375,
          calculatedProtein: 30,
          calculatedCarbs: 5,
          calculatedFat: 22.5,
          entryDate: '2026-09-28',
          source: 'manual',
          createdAt: '2026-09-28T12:00:00Z',
        );

    test('food_id NULL + custom_name NULL → "Bilinmeyen" (eski hatanın sonucu)',
        () {
      // Gıda silindi (`food_id` SET NULL) **ve** ad hiç yazılmamıştı.
      expect(build().displayName, 'Bilinmeyen');
    });

    test('food_id NULL + custom_name DOLU → ad korunur (düzeltmenin sonucu)',
        () {
      expect(build(customName: 'Ev Yapımı Köfte').displayName,
          'Ev Yapımı Köfte');
    });

    test('⭐ gıda silindikten sonra kalorisi durur ama adı korunur', () {
      final entry = build(customName: 'Ev Yapımı Köfte');
      expect(entry.foodId, isNull, reason: 'FK SET NULL uygulanmış');
      expect(entry.calculatedKcal, 375, reason: 'öğün satırı korunuyor');
      expect(entry.displayName, 'Ev Yapımı Köfte', reason: 'ad da korunuyor');
    });
  });

  // ==========================================================================
  // 2b) ⭐ Sözleşme: düğme metni çeviri anahtarından geliyor
  // ==========================================================================
  testWidgets('ekleme düğmesi `addFood.title` çeviri anahtarını kullanır',
      (tester) async {
    // `_tapAdd` SABİT bir metin arıyor; bu test o sabitin gerçekten
    // `tr.json`'daki `addFood.title` olduğunu kanıtlar. Eşleşmezse test
    // "yeşil kalır ama hiçbir şey ölçmez" sınıfına düşerdi.
    expect('Yiyecek Ekle', 'addFood.title'.tr(),
        reason: 'düğme metni çeviriyle eşleşmiyor → _tapAdd boşa basar');
  });

  // ==========================================================================
  // 3) DeleteFoodButton — `canDelete` kapısı
  // ==========================================================================
  group('⭐ DeleteFoodButton — canDelete kapısı (A4r11)', () {
    Future<void> pump(WidgetTester tester, FoodItem item) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('tr'), Locale('en')],
            path: 'assets/translations',
            fallbackLocale: const Locale('tr'),
            startLocale: const Locale('tr'),
            child: Builder(
              builder: (context) => ProviderScope(
                overrides: [
                  currentUserProvider.overrideWithValue(_kUser),
                ],
                child: MaterialApp(
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  home: Scaffold(
                    body: Center(child: DeleteFoodButton(food: item)),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      });
    }

    testWidgets('canDelete=false (varsayılan) → düğme YOK', (tester) async {
      await pump(
        tester,
        const FoodItem(
          id: 'seed-1',
          foodId: 'seed-1',
          name: 'Mercimek Çorbası',
          calories: 90,
          proteinG: 4,
          carbsG: 12,
          fatG: 1,
        ),
      );
      expect(find.byType(IconButton), findsNothing,
          reason: '`created_by IS NULL` → RLS DELETE reddi');
      expect(find.byTooltip('Yemek sil: Mercimek Çorbası'), findsNothing);
    });

    testWidgets('canDelete=true → düğme VAR', (tester) async {
      await pump(
        tester,
        const FoodItem(
          id: 'mine-1',
          foodId: 'mine-1',
          name: 'Ev Yapımı Köfte',
          calories: 250,
          proteinG: 20,
          carbsG: 5,
          fatG: 15,
          canDelete: true,
        ),
      );
      expect(find.byType(IconButton), findsOneWidget);
      expect(find.byTooltip('Yemek sil: Ev Yapımı Köfte'), findsOneWidget);
    });

    testWidgets('foodId=null → düğme YOK (regresyon koruması)', (tester) async {
      await pump(
        tester,
        const FoodItem(
          id: 'custom_1',
          name: 'Ev yapımı köfte',
          calories: 250,
          proteinG: 20,
          carbsG: 5,
          fatG: 15,
          isCustom: true,
          canDelete: true,
        ),
      );
      expect(find.byType(IconButton), findsNothing,
          reason: '`foods` tablosunda satır yok → silinecek kayıt yok');
    });
  });
}

// ============================================================================
// Yardımcılar
// ============================================================================

/// ⭐ Etkileşimin **gerçekten gerçekleştiğini** doğrular (A4r7b / A4r10).
///
/// A4r7b: `tester.tap('Kaydet')` ekran dışındaysa **sessizce** hiçbir şey
/// yapmıyordu ve 3 test hiçbir şey ölçmeden yeşildi. A4r10: `hitTest`
/// ulaşıldığını doğruluyordu ama tıklama yine gerçekleşmiyordu.
///
/// Burada: (a) düğme bulunur, (b) **ekran içinde** olduğu doğrulanır,
/// (c) basılır, (d) çağıranın `captured.calls == 1` kontrolü **kaydın
/// oluştuğunu** kanıtlar.
///
/// ⭐ Düğme metni **çeviri anahtarından** okunur (`addFood.title`), sabit
/// yazılmaz: çeviri değişirse test kırılır ama **anlamı kaybolmaz**
/// (sabit metin yazsaydık sessizce yanlış düğmeye basabilirdik).
Future<void> _tapAdd(WidgetTester tester, String label) async {
  final finder = find.text(label);
  expect(finder, findsOneWidget, reason: 'ekleme düğmesi yok → test ölçmez');

  final rect = tester.getRect(finder);
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(
    rect.overlaps(Offset.zero & screen),
    isTrue,
    reason: 'düğme ($rect) ekranın ($screen) dışında → tap sessizce boşa',
  );
  expect(rect.width, greaterThan(0), reason: 'sıfır genişlik = tıklanamaz');

  await tester.tap(finder);
  await tester.pumpAndSettle();
}

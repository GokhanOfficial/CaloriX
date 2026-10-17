import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/recognized_food.dart';
import '../supabase/supabase_client_provider.dart';

/// Yemek tanıma (foto / metin) edge fonksiyonlarını sarmalar —
/// web `src/components/dialogs/UnifiedFoodDialog.tsx` invoke kontratı.
///
///  - `recognize-food`: gövde `{ image_base64: <full data URL>, additional_text? }`.
///    Depolama yükleme YOK; görsel doğrudan base64 data URL olarak gönderilir.
///    Sunucu `data:image/jpeg;base64,` önekini eksikse ekler (biz yine de
///    tam data URL göndeririz — web ile aynı).
///  - `recognize-food-text`: gövde `{ text }`. Aynı yanıt şekli.
///
/// Yanıt: `{ foods: [...], description? }` → [RecognitionResult].
/// Hata durumunda edge fonksiyonu `{ error: ... }` döndürür; bu durumda
/// [RecognitionException] fırlatılır.
///
/// ⭐ TEK SEFERLİK OTOMATİK YENİDEN DENE (2026-10-17, canlı ölçüm):
/// AI sağlayıcısının vision yolu doygunluk anlarında isteklerin ~%40'ını
/// 60-74 s beklettikten sonra ret ediyor (`502 "AI servisi şu anda yanıt
/// vermiyor"`; sağlayıcı deseni A1r11'in "403 all_providers_failed"
/// ölçümünün aynısı). Ret penceresi kısa olduğundan kullanıcıya hatayı
/// göstermek yerine BİR kez sessiz yeniden deneme yapılır:
///  - yalnız 502 (sağlayıcı ret) ve 429 (rate limit) durumlarında —
///    401 (oturum), 400 (doğrulama) gibi deterministik hatalarda
///    yeniden deneme anlamsızdır ve kullanıcıyı gereksiz bekletir;
///  - denemeler arası bekleme yok: ret zaten 60 s+ sonra geliyor,
///    ekstra bekleme toplam süreyi 3 dakikaya taşırır.
///  - ikinci deneme de başarısızsa hata olduğu gibi yukarı taşınır.
class RecognitionRepository {
  RecognitionRepository(this._client);

  final SupabaseClient _client;

  /// Fotoğraftan yemek tanır (web `recognize-food` invoke).
  ///
  /// [image] — `image_picker`/`camera` paketinden gelen `XFile`.
  /// [additionalText] — opsiyonel porsiyon/ipucu metni.
  Future<RecognitionResult> recognizeFood(
    XFile image, {
    String? additionalText,
  }) async {
    final bytes = await image.readAsBytes();
    final mime = image.mimeType ?? 'image/jpeg';
    final dataUrl = _toDataUrl(mime, bytes);

    return _invoke('recognize-food', {
      'image_base64': dataUrl,
      if (additionalText != null && additionalText.isNotEmpty)
        'additional_text': additionalText,
    });
  }

  /// Metinden yemek tanır (web `recognize-food-text` invoke).
  Future<RecognitionResult> recognizeFoodText(String text) async {
    return _invoke('recognize-food-text', {'text': text});
  }

  Future<RecognitionResult> _invoke(
    String fn,
    Map<String, dynamic> body,
  ) async {
    FunctionResponse response;
    try {
      response = await _client.functions.invoke(fn, body: body);
    } on FunctionException catch (e) {
      // Sağlayıcı doygunluğu (502) veya rate-limit (429): bir kez sessiz
      // yeniden dene — retler kısa pencereli, ikinci deneme genelde tutar.
      if (e.status == 502 || e.status == 429) {
        try {
          response = await _client.functions.invoke(fn, body: body);
        } on FunctionException catch (e2) {
          throw RecognitionException(_errorFrom(e2.details, e2.status));
        }
      } else {
        // Non-2xx durumunda `functions.invoke` **istisna fırlatır**; hata
        // gövdesi `details` alanındadır. Yakalanmazsa çağıran ekran ham
        // `FunctionHttpException` mesajını kullanıcıya gösterirdi; burada
        // sunucunun döndüğü `{error}` metni kullanıcıya taşınır.
        throw RecognitionException(_errorFrom(e.details, e.status));
      }
    }

    final data = response.data as Map<String, dynamic>?;

    if (data == null) {
      throw const RecognitionException('Tanıma yanıtı boş.');
    }
    if (data['error'] != null) {
      throw RecognitionException(data['error'].toString());
    }
    return RecognitionResult.fromJson(data);
  }

  /// Hata gövdesinden okunabilir mesaj çıkarır.
  static String _errorFrom(Object? details, int status) {
    if (details is Map) {
      final err = details['error'];
      if (err != null) return err.toString();
    }
    if (details is String && details.trim().isNotEmpty) {
      return details.length > 200 ? '${details.substring(0, 200)}…' : details;
    }
    return 'Tanıma başarısız (HTTP $status).';
  }

  /// `data:<mime>;base64,<b64>` biçiminde tam data URL üretir.
  static String _toDataUrl(String mime, Uint8List bytes) {
    final b64 = base64Encode(bytes);
    return 'data:$mime;base64,$b64';
  }
}

/// Tanıma hatası — edge fonksiyonu `error` döndürdüğünde veya non-2xx
/// HTTP durumunda fırlatılır.
class RecognitionException implements Exception {
  const RecognitionException(this.message);
  final String message;

  @override
  String toString() => 'RecognitionException: $message';
}

final recognitionRepositoryProvider = Provider<RecognitionRepository>((ref) {
  return RecognitionRepository(ref.watch(supabaseClientProvider));
});

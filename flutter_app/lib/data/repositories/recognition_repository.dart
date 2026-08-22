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
    final response = await _client.functions.invoke(fn, body: body);
    final data = response.data as Map<String, dynamic>?;

    if (data == null) {
      throw RecognitionException('Tanıma yanıtı boş.');
    }
    if (data.containsKey('error')) {
      throw RecognitionException(
        (data['error'] as String?) ?? 'Tanıma başarısız.',
      );
    }
    return RecognitionResult.fromJson(data);
  }

  /// `data:<mime>;base64,<b64>` biçiminde tam data URL üretir.
  static String _toDataUrl(String mime, Uint8List bytes) {
    final b64 = base64Encode(bytes);
    return 'data:$mime;base64,$b64';
  }
}

/// Tanıma hatası — edge fonksiyonu `error` döndürdüğünde fırlatılır.
class RecognitionException implements Exception {
  const RecognitionException(this.message);
  final String message;

  @override
  String toString() => 'RecognitionException: $message';
}

final recognitionRepositoryProvider = Provider<RecognitionRepository>((ref) {
  return RecognitionRepository(ref.watch(supabaseClientProvider));
});

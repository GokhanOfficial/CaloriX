import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Sayısal metin alanları için paylaşılan helper'lar.
///
/// Tüm alanlar **dışarıdan verilen** [TextEditingController] kullanır —
/// `build` içinde controller yaratılmaz. Bu, her tuş vuruşunda parent
/// `setState` çağrılsa bile [TextField]'ın odakını korur (controller State
/// içinde稳定 tutulur, `dispose`'da bırakılır).
///
/// Kullanım:
/// ```dart
/// late final TextEditingController _amountController;
/// initState: _amountController = TextEditingController(text: formatAmount(100));
/// dispose:  _amountController.dispose();
/// NumField(controller: _amountController, label: 'Miktar', suffix: 'g/ml');
/// ```

/// Tam genişlikli (veya [flex] ile esnek) ondalıklı sayı alanı.
class NumField extends StatelessWidget {
  const NumField({
    super.key,
    required this.controller,
    required this.label,
    this.suffix,
    this.flex,
  });

  final TextEditingController controller;
  final String label;
  final String? suffix;

  /// `null` değilse `Expanded(flex:)` ile sarılır; `null` ise doğrudan döner.
  final int? flex;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
    );
    if (flex == null) return field;
    return Expanded(flex: flex!, child: field);
  }
}

/// Dar (varsayılan 72px) ondalıklı sayı alanı — 100g başına makrolar için.
class MiniNumField extends StatelessWidget {
  const MiniNumField({
    super.key,
    required this.controller,
    required this.label,
    this.width = 72,
  });

  final TextEditingController controller;
  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// Nullable genişletilmiş besin alanı — boş değer kabul eder.
///
/// `build` içinde controller metni yeniden set edilmez; caller controller'ı
/// yönetir. `isInt` ise tam sayı girilmesi beklenir (NOVA skoru).
class OptNumField extends StatelessWidget {
  const OptNumField({
    super.key,
    required this.controller,
    required this.label,
    this.isInt = false,
  });

  final TextEditingController controller;
  final String label;
  final bool isInt;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// Tek karakterli metin alanı (Nutri-Score A-E).
class OptTextField extends StatelessWidget {
  const OptTextField({
    super.key,
    required this.controller,
    required this.label,
    this.maxLength = 1,
  });

  final TextEditingController controller;
  final String label;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// Sayısal değerleri metne dönüştürür — tam sayıysa ondalıksız, değilse 1 ondalık.
/// Controller `initState`'te seed edilirken kullanılır.
String formatAmount(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1);
}

/// Nullable sayıyı metne dönüştürür — `null` ise boş string.
String formatOptAmount(double? v, {bool isInt = false}) {
  if (v == null) return '';
  if (isInt) return v.round().toString();
  return formatAmount(v);
}

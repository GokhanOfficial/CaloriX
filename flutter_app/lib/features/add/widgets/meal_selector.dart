import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';

/// Paylaşılan öğün seçici — 4 segmentli `SegmentedButton<MealType>`
/// (emoji + `meals.<name>`).
///
/// Tüm yemek ekleme akışlarındaki `DropdownButtonFormField<MealType>`
/// yerine kullanılır (`add_page`, `add_from_food_dialog`,
/// `add_manual_entry_dialog`, `recognition_confirm_dialog`).
/// `value`/`onChanged` arayüzü dropdown ile
/// aynıdır.
///
/// Dar ekran (360dp) taşma riski: `SegmentedButton` bir satıra sığmazsa
/// yatay `SingleChildScrollView` ile sarılır (gelecek fallback).
class MealSegmentedButton extends StatelessWidget {
  const MealSegmentedButton({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final MealType value;
  final ValueChanged<MealType> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<MealType>(
      style: const ButtonStyle(
        visualDensity: VisualDensity(horizontal: -3, vertical: -2),
      ),
      segments: [
        for (final t in MealType.values)
          ButtonSegment(
            value: t,
            label: Text('meals.${t.name}'.tr()),
            icon: Text(t.emoji, style: const TextStyle(fontSize: 14)),
          ),
      ],
      selected: {value},
      onSelectionChanged: (s) {
        if (s.isNotEmpty) onChanged(s.first);
      },
      showSelectedIcon: false,
    );
  }
}

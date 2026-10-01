import 'package:flutter/material.dart';

import '../../domain/models/tunis_dates.dart';
import 'design.dart';

/// "JJ/MM/AAAA", the form every expiry is read back in.
String dayMonthYear(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

/// An expiry date chosen on a calendar instead of typed.
class ExpiryDateField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool enabled, required;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final Key? fieldKey;
  const ExpiryDateField({
    super.key,
    this.fieldKey,
    required this.controller,
    this.label = 'Date de péremption',
    this.enabled = true,
    this.required = true,
    this.hint,
    this.onChanged,
  });

  DateTime get _initial {
    try {
      final value = TunisDates.expiry(controller.text);
      return DateTime.parse(value);
    } catch (_) {
      final now = DateTime.now();
      return DateTime(now.year + 1, now.month, now.day);
    }
  }

  Future<void> _pick(BuildContext context) async {
    final initial = _initial;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: label,
      cancelText: 'Annuler',
      confirmText: 'Choisir',
      initialEntryMode: DatePickerEntryMode.calendar,
    );
    if (picked == null) return;
    controller.text = dayMonthYear(picked);
    onChanged?.call(controller.text);
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    key: fieldKey,
    controller: controller,
    readOnly: true,
    enabled: enabled,
    onTap: enabled ? () => _pick(context) : null,
    decoration: InputDecoration(
      labelText: label,
      hintText: 'Choisir une date',
      helperText: hint,
      helperMaxLines: 2,
      suffixIcon: IconButton(
        tooltip: 'Ouvrir le calendrier',
        onPressed: enabled ? () => _pick(context) : null,
        icon: const Icon(AppIcons.calendar),
      ),
    ),
    validator: (value) => required && (value?.trim().isEmpty ?? true)
        ? 'Choisissez une date.'
        : null,
  );
}

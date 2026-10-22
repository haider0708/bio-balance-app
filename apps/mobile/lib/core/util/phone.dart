/// Tunisian mobile numbers, as people write them: "21 345 678", "+216 21 345 678", "00216 21345678",
/// "216-21-345-678". Every form becomes the one canonical "+21621345678" (what the server stores and
/// WhatsApp needs). The same rules as the server's `core/phone.ts`.
String? normalizeTunisianPhone(String input) {
  var digits = input.trim().replaceAll(RegExp(r'[\s.\-()]'), '');
  late final String national;
  if (digits.startsWith('+')) {
    digits = digits.substring(1);
  } else if (digits.startsWith('00')) {
    digits = digits.substring(2);
  } else if (RegExp(r'^\d{8}$').hasMatch(digits)) {
    national = digits;
    return RegExp(r'^[2-9]').hasMatch(national) ? '+216$national' : null;
  }
  if (!RegExp(r'^\d+$').hasMatch(digits) || !digits.startsWith('216')) {
    return null;
  }
  national = digits.substring(3);
  if (!RegExp(r'^\d{8}$').hasMatch(national)) return null;
  return RegExp(r'^[2-9]').hasMatch(national) ? '+216$national' : null;
}

/// "+216 21 345 678", to show a number back to the person who typed it.
String formatPhone(String e164) {
  final m = RegExp(r'^\+216(\d{2})(\d{3})(\d{3})$').firstMatch(e164);
  return m == null ? e164 : '+216 ${m[1]} ${m[2]} ${m[3]}';
}

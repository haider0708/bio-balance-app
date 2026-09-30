/// What the parcel's QR carries: the delivery and a code only the server can
/// derive. The code is sent with the reception as proof; the server decides.
class TicketScan {
  final String deliveryId, code;
  const TicketScan(this.deliveryId, this.code);
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final _code = RegExp(r'^[A-Za-z0-9_-]{16,64}$');

  /// Null for anything that is not a BioBalance delivery QR.
  static TicketScan? parse(String raw) {
    final parts = raw.trim().split('.');
    if (parts.length != 3 || parts[0] != 'BB1') return null;
    if (!_uuid.hasMatch(parts[1]) || !_code.hasMatch(parts[2])) return null;
    return TicketScan(parts[1].toLowerCase(), parts[2]);
  }
}

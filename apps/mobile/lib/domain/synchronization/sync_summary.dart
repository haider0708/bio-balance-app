/// Account-wide status of durable work on this device, independently of the
/// store currently displayed. Confirmed work stays here until its server state
/// has been installed atomically with removal of the provisional effect.
class SyncSummary {
  final int waiting, retrying, blocked, attention, confirming;
  final DateTime? nextAttemptAt;
  const SyncSummary({
    this.waiting = 0,
    this.retrying = 0,
    this.blocked = 0,
    this.attention = 0,
    this.confirming = 0,
    this.nextAttemptAt,
  });
  int get total => waiting + retrying + blocked + attention + confirming;
  String get label {
    if (attention > 0) return '$attention à vérifier';
    if (waiting + retrying > 0) return '${waiting + retrying} à envoyer';
    if (blocked > 0) return '$blocked en attente d’une opération liée';
    if (confirming > 0) return '$confirming confirmée(s) · actualisation';
    return 'Tout est synchronisé';
  }
}

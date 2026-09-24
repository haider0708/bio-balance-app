import 'models.dart';

/// Reception quantities are observations, never inferred positive stock receipts.
class ReceiptPlan {
  final List<Json> expected, allocations;
  const ReceiptPlan(this.expected, this.allocations);
  int expectedUnits(String product) => expected
      .where((line) => line['productId'] == product)
      .fold(0, (sum, line) => sum + integer(line['quantity']));
  int enteredUnits(String product) => allocations
      .where((line) => line['productId'] == product)
      .fold(0, (sum, line) => sum + integer(line['quantity']));
  int remaining(String product) =>
      (expectedUnits(product) - enteredUnits(product)).clamp(0, 1000000);
  int get sellable => units('sellable');
  int get damaged => units('damaged');
  int get refused => units('refused');
  int units(String condition) => allocations
      .where((line) => (line['condition'] ?? 'sellable') == condition)
      .fold(0, (sum, line) => sum + integer(line['quantity']));
  bool get requiresExplanation =>
      damaged > 0 ||
      refused > 0 ||
      expected.any(
        (line) =>
            enteredUnits(line['productId']) > expectedUnits(line['productId']),
      );
}

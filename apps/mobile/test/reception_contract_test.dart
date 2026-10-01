import 'package:biobalance/data/services/api/generated/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a delivery waiting for validation decodes with its claim', () {
    final delivery = DeliveryDto.fromJson({
      'id': 'd',
      'organizationId': 'o',
      'storeId': 's',
      'orderId': 'x',
      'lines': [
        {
          'productId': 'p',
          'quantity': 10,
          'allocations': [
            {'batch': 'A', 'expiry': '2030-05-31', 'quantity': 10},
          ],
        },
      ],
      'sourceOrganizationId': null,
      'sourceStoreId': null,
      'ticketNumber': 'BL-2026-000001',
      'ticketVersion': 1,
      'claim': {
        'lines': [
          {
            'productId': 'p',
            'batch': 'A',
            'expiry': '2030-05-31',
            'quantity': 7,
            'condition': 'sellable',
          },
        ],
        'note': '',
        'manualReason': 'Pas de caméra',
        'claimedBy': 'u',
        'claimedAt': '2026-10-01T10:00:00.000Z',
      },
      'status': 'pending_review',
      'version': 2,
      'dispatchedAt': '2026-10-01T09:00:00.000Z',
      'receivedAt': null,
    });
    expect(delivery.status, 'pending_review');
    expect(delivery.claim!.manualReason, 'Pas de caméra');
    expect(delivery.claim!.lines.single.quantity, 7);
  });

  test('a delivery with no claim yet still decodes', () {
    final delivery = DeliveryDto.fromJson({
      'id': 'd',
      'organizationId': 'o',
      'storeId': 's',
      'orderId': 'x',
      'lines': [],
      'sourceOrganizationId': null,
      'sourceStoreId': null,
      'ticketNumber': 'BL-2026-000002',
      'ticketVersion': 1,
      'claim': null,
      'status': 'dispatched',
      'version': 1,
      'dispatchedAt': '2026-10-01T09:00:00.000Z',
      'receivedAt': null,
    });
    expect(delivery.claim, isNull);
  });
}

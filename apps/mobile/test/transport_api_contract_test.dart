import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'generated/contract_examples.dart';

void main() {
  final path = Platform.environment['BIOBALANCE_CONTRACT_FIXTURE'];
  test(
    'generated Dart transport decodes and preserves every JSON endpoint response from the real API',
    () async {
      final fixtures = jsonDecode(await File(path!).readAsString()) as List;
      expect(fixtures.length, greaterThanOrEqualTo(42));
      for (final fixture in fixtures) {
        expect(
          decodeResponse(fixture['operationId'], fixture['value']),
          fixture['value'],
          reason: fixture['operationId'],
        );
      }
    },
    skip: path == null
        ? 'Run npm run test:contracts with the isolated API/database.'
        : false,
  );
}

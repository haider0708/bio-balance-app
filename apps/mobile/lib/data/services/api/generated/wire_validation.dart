// GENERATED schema matching for tagged wire unions; domain validation is separate.
Object? freezeJson(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(
      value.map((k, v) => MapEntry(k as String, freezeJson(v))),
    );
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(freezeJson));
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  throw const FormatException('Invalid JSON value');
}

int wireInteger(Object? value) {
  if (value is int) return value;
  throw const FormatException('Entier invalide dans la réponse du serveur.');
}

bool matchesWire(Object? value, String name) =>
    _matches(value, _schemas[name]!);
bool _matches(Object? value, Map<String, dynamic> schema) {
  if (schema[r'$ref'] case final String ref) {
    return matchesWire(value, ref.split('/').last);
  }
  if (schema['const'] != null && value != schema['const']) return false;
  if (schema['enum'] case final List values) {
    if (!values.contains(value)) return false;
  }
  if (schema['oneOf'] case final List variants) {
    return variants
            .where((s) => _matches(value, Map<String, dynamic>.from(s)))
            .length ==
        1;
  }
  if (schema['anyOf'] case final List variants) {
    return variants.any((s) => _matches(value, Map<String, dynamic>.from(s)));
  }
  switch (schema['type']) {
    case 'null':
      return value == null;
    case 'string':
      return value is String;
    case 'integer':
      return value is int;
    case 'number':
      return value is num;
    case 'boolean':
      return value is bool;
    case 'array':
      return value is List && value.every((v) => _matches(v, schema['items']));
    case 'object':
      if (value is! Map) return false;
      final properties = Map<String, dynamic>.from(schema['properties'] ?? {});
      if (!(schema['required'] as List? ?? []).every(value.containsKey)) {
        return false;
      }
      for (final entry in value.entries) {
        final p = properties[entry.key];
        if (p != null) {
          if (!_matches(entry.value, p)) return false;
        } else if (schema['additionalProperties'] == false) {
          return false;
        } else if (schema['additionalProperties'] is Map &&
            !_matches(entry.value, schema['additionalProperties'])) {
          return false;
        }
      }
      return true;
  }
  return true;
}

const Map<String, Map<String, dynamic>> _schemas = {
  "JsonValue": {
    "description": "Versioned audit metadata; values are JSON primitives, arrays or objects. Never used as an endpoint body or result.",
    "anyOf": [
      {"type": "null"},
      {"type": "string"},
      {"type": "number"},
      {"type": "boolean"},
      {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/JsonValue"},
      },
      {
        "type": "object",
        "additionalProperties": {"\$ref": "#/components/schemas/JsonValue"},
      },
    ],
  },
  "Money": {
    "type": "object",
    "properties": {
      "currency": {"const": "TND", "type": "string"},
      "millimes": {"type": "string", "pattern": "^(0|[1-9][0-9]*)\$"},
    },
    "required": ["currency", "millimes"],
    "additionalProperties": false,
  },
  "User": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "email": {"type": "string"},
      "name": {"type": "string"},
      "platformAdmin": {"type": "boolean"},
      "sessionId": {"type": "string", "format": "uuid"},
    },
    "required": ["id", "email", "name", "platformAdmin"],
    "additionalProperties": false,
  },
  "LoginResponse": {
    "type": "object",
    "properties": {
      "token": {"type": "string"},
      "expiresAt": {"type": "string", "format": "date-time"},
      "user": {"\$ref": "#/components/schemas/User"},
    },
    "required": ["token", "expiresAt", "user"],
    "additionalProperties": false,
  },
  "Ok": {
    "type": "object",
    "properties": {
      "ok": {"const": true, "type": "boolean"},
    },
    "required": ["ok"],
    "additionalProperties": false,
  },
  "Activated": {
    "type": "object",
    "properties": {
      "ok": {"const": true, "type": "boolean"},
      "email": {"type": "string"},
    },
    "required": ["ok", "email"],
    "additionalProperties": false,
  },
  "Invitation": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "email": {"type": "string"},
      "status": {"const": "invited", "type": "string"},
      "expiresAt": {"type": "string", "format": "date-time"},
    },
    "required": ["id", "email", "status", "expiresAt"],
    "additionalProperties": false,
  },
  "InvitationSummary": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "email": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
      "expiresAt": {"type": "string", "format": "date-time"},
    },
    "required": ["id", "email", "expiresAt"],
    "additionalProperties": false,
  },
  "Message": {
    "type": "object",
    "properties": {
      "message": {"type": "string"},
    },
    "required": ["message"],
    "additionalProperties": false,
  },
  "Count": {
    "type": "object",
    "properties": {
      "count": {"type": "integer"},
    },
    "required": ["count"],
    "additionalProperties": false,
  },
  "Health": {
    "type": "object",
    "properties": {
      "status": {"const": "ok", "type": "string"},
    },
    "required": ["status"],
    "additionalProperties": false,
  },
  "Organization": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "name": {"type": "string"},
      "createdAt": {"type": "string", "format": "date-time"},
      "status": {"type": "string"},
      "statusReason": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
      "statusChangedAt": {
        "anyOf": [
          {"type": "string", "format": "date-time"},
          {"type": "null"},
        ],
      },
      "statusChangedBy": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "imageId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "phone": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
      "version": {"type": "integer"},
    },
    "required": ["id", "name", "createdAt"],
    "additionalProperties": false,
  },
  "Store": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "name": {"type": "string"},
      "address": {"type": "string"},
      "city": {"type": "string"},
      "phone": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
      "imageId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "timezone": {"type": "string"},
      "onboardingStep": {"type": "integer"},
      "workingAlone": {"type": "boolean"},
      "noOpeningStock": {"type": "boolean"},
      "version": {"type": "integer"},
      "createdAt": {"type": "string", "format": "date-time"},
      "status": {"type": "string"},
      "statusReason": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
      "statusChangedAt": {
        "anyOf": [
          {"type": "string", "format": "date-time"},
          {"type": "null"},
        ],
      },
      "statusChangedBy": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
    },
    "required": [
      "id",
      "organizationId",
      "name",
      "address",
      "city",
      "phone",
      "imageId",
      "timezone",
      "onboardingStep",
      "workingAlone",
      "noOpeningStock",
      "version",
      "createdAt",
    ],
    "additionalProperties": false,
  },
  "StoreAccess": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "name": {"type": "string"},
      "address": {"type": "string"},
      "city": {"type": "string"},
      "phone": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
      "imageId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "timezone": {"type": "string"},
      "onboardingStep": {"type": "integer"},
      "workingAlone": {"type": "boolean"},
      "noOpeningStock": {"type": "boolean"},
      "version": {"type": "integer"},
      "createdAt": {"type": "string", "format": "date-time"},
      "organizationName": {"type": "string"},
      "permissions": {
        "type": "array",
        "items": {
          "type": "string",
          "enum": ["sell", "receive", "manage"],
        },
      },
      "status": {"type": "string"},
      "statusReason": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
      "statusChangedAt": {
        "anyOf": [
          {"type": "string", "format": "date-time"},
          {"type": "null"},
        ],
      },
      "statusChangedBy": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
    },
    "required": [
      "id",
      "organizationId",
      "name",
      "address",
      "city",
      "phone",
      "imageId",
      "timezone",
      "onboardingStep",
      "workingAlone",
      "noOpeningStock",
      "version",
      "createdAt",
      "permissions",
    ],
    "additionalProperties": false,
  },
  "Membership": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "userId": {"type": "string", "format": "uuid"},
      "permissions": {
        "type": "array",
        "items": {
          "type": "string",
          "enum": ["sell", "receive", "manage"],
        },
      },
      "active": {"type": "boolean"},
      "createdAt": {"type": "string", "format": "date-time"},
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "userId",
      "permissions",
      "active",
      "createdAt",
    ],
    "additionalProperties": false,
  },
  "TeamMember": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "userId": {"type": "string", "format": "uuid"},
      "permissions": {
        "type": "array",
        "items": {
          "type": "string",
          "enum": ["sell", "receive", "manage"],
        },
      },
      "active": {"type": "boolean"},
      "createdAt": {"type": "string", "format": "date-time"},
      "membershipId": {"type": "string", "format": "uuid"},
      "name": {"type": "string"},
      "email": {"type": "string"},
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "userId",
      "permissions",
      "active",
      "createdAt",
      "membershipId",
      "name",
      "email",
    ],
    "additionalProperties": false,
  },
  "Person": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "name": {"type": "string"},
    },
    "required": ["id", "name"],
    "additionalProperties": false,
  },
  "Product": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "reference": {"type": "string"},
      "name": {"type": "string"},
      "barcode": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
      "description": {"type": "string"},
      "imageId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "active": {"type": "boolean"},
      "version": {"type": "integer"},
      "updatedAt": {"type": "string", "format": "date-time"},
      "category": {"type": "string"},
      "range": {"type": "string"},
      "packageSize": {"type": "string"},
      "instructions": {"type": "string"},
      "ingredients": {"type": "string"},
      "precautions": {"type": "string"},
      "referencePriceMillimes": {
        "anyOf": [
          {"type": "string", "pattern": "^-?[0-9]+\$"},
          {"type": "null"},
        ],
      },
      "priceStatus": {"type": "string"},
      "sourceUrls": {
        "type": "array",
        "items": {"type": "string"},
      },
    },
    "required": [
      "id",
      "reference",
      "name",
      "barcode",
      "description",
      "imageId",
      "active",
      "version",
      "updatedAt",
    ],
    "additionalProperties": false,
  },
  "StoreProduct": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "productId": {"type": "string", "format": "uuid"},
      "priceMillimes": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "threshold": {"type": "integer"},
      "pointsPerUnit": {"type": "integer"},
      "pointsConfigured": {"type": "boolean"},
      "zeroPointsConfirmed": {"type": "boolean"},
      "version": {"type": "integer"},
      "priceConfigured": {"type": "boolean"},
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "productId",
      "priceMillimes",
      "threshold",
      "pointsPerUnit",
      "pointsConfigured",
      "zeroPointsConfirmed",
      "version",
    ],
    "additionalProperties": false,
  },
  "InventoryLot": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "productId": {"type": "string", "format": "uuid"},
      "batch": {"type": "string"},
      "expiry": {"type": "string", "format": "date-time"},
      "sellable": {"type": "integer"},
      "damaged": {"type": "integer"},
      "version": {"type": "integer"},
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "productId",
      "batch",
      "expiry",
      "sellable",
      "damaged",
      "version",
    ],
    "additionalProperties": false,
  },
  "StockMovement": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "lotId": {"type": "string", "format": "uuid"},
      "quantity": {"type": "integer"},
      "bucket": {"type": "string"},
      "reason": {"type": "string"},
      "sourceId": {"type": "string", "format": "uuid"},
      "actorId": {"type": "string", "format": "uuid"},
      "operationId": {"type": "string", "format": "uuid"},
      "createdAt": {"type": "string", "format": "date-time"},
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "lotId",
      "quantity",
      "bucket",
      "reason",
      "sourceId",
      "actorId",
      "operationId",
      "createdAt",
    ],
    "additionalProperties": false,
  },
  "SaleAllocation": {
    "type": "object",
    "properties": {
      "lotId": {"type": "string", "format": "uuid"},
      "quantity": {"type": "integer"},
    },
    "required": ["lotId", "quantity"],
    "additionalProperties": false,
  },
  "AcceptedSaleLine": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "productId": {"type": "string", "format": "uuid"},
      "quantity": {"type": "integer"},
      "unitPriceMillimes": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "allocations": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/SaleAllocation"},
      },
      "pointsPerUnit": {"type": "integer"},
    },
    "required": [
      "id",
      "productId",
      "quantity",
      "unitPriceMillimes",
      "allocations",
      "pointsPerUnit",
    ],
    "additionalProperties": false,
  },
  "SaleRecord": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "sellerId": {"type": "string", "format": "uuid"},
      "occurredAt": {"type": "string", "format": "date-time"},
      "version": {"type": "integer"},
      "lines": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/AcceptedSaleLine"},
      },
      "returned": {
        "type": "object",
        "additionalProperties": {"type": "integer"},
      },
      "totalMillimes": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "earnedPoints": {"type": "string", "pattern": "^-?[0-9]+\$"},
    },
    "required": [
      "id",
      "sellerId",
      "occurredAt",
      "version",
      "lines",
      "returned",
      "totalMillimes",
      "earnedPoints",
    ],
    "additionalProperties": false,
  },
  "Sale": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "sellerId": {"type": "string", "format": "uuid"},
      "occurredAt": {"type": "string", "format": "date-time"},
      "version": {"type": "integer"},
      "lines": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/AcceptedSaleLine"},
      },
      "returned": {
        "type": "object",
        "additionalProperties": {"type": "integer"},
      },
      "totalMillimes": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "earnedPoints": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "acceptedAt": {"type": "string", "format": "date-time"},
    },
    "required": [
      "id",
      "sellerId",
      "occurredAt",
      "version",
      "lines",
      "returned",
      "totalMillimes",
      "earnedPoints",
      "organizationId",
      "storeId",
      "acceptedAt",
    ],
    "additionalProperties": false,
  },
  "SaleRevision": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "saleId": {"type": "string", "format": "uuid"},
      "version": {"type": "integer"},
      "editorId": {"type": "string", "format": "uuid"},
      "reason": {"type": "string"},
      "before": {
        "anyOf": [
          {"\$ref": "#/components/schemas/SaleRecord"},
          {"type": "null"},
        ],
      },
      "after": {"\$ref": "#/components/schemas/SaleRecord"},
      "operationId": {"type": "string", "format": "uuid"},
      "createdAt": {"type": "string", "format": "date-time"},
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "saleId",
      "version",
      "editorId",
      "reason",
      "before",
      "after",
      "operationId",
      "createdAt",
    ],
    "additionalProperties": false,
  },
  "SaleDetails": {
    "type": "object",
    "properties": {
      "sale": {"\$ref": "#/components/schemas/Sale"},
      "revisions": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/SaleRevision"},
      },
      "people": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/Person"},
      },
    },
    "required": ["sale", "revisions", "people"],
    "additionalProperties": false,
  },
  "PointsAccount": {
    "type": "object",
    "properties": {
      "balance": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "reserved": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "userId": {"type": "string", "format": "uuid"},
    },
    "required": ["balance", "reserved"],
    "additionalProperties": false,
  },
  "PointsEntry": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "userId": {"type": "string", "format": "uuid"},
      "amount": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "kind": {"type": "string"},
      "sourceId": {"type": "string", "format": "uuid"},
      "operationId": {"type": "string", "format": "uuid"},
      "createdAt": {"type": "string", "format": "date-time"},
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "userId",
      "amount",
      "kind",
      "sourceId",
      "operationId",
      "createdAt",
    ],
    "additionalProperties": false,
  },
  "Reward": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "title": {"type": "string"},
      "description": {"type": "string"},
      "imageId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "cost": {"type": "integer"},
      "productId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "quantity": {"type": "integer"},
      "active": {"type": "boolean"},
      "version": {"type": "integer"},
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "title",
      "description",
      "imageId",
      "cost",
      "productId",
      "quantity",
      "active",
      "version",
    ],
    "additionalProperties": false,
  },
  "RewardClaim": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "userId": {"type": "string", "format": "uuid"},
      "rewardId": {"type": "string", "format": "uuid"},
      "title": {"type": "string"},
      "cost": {"type": "integer"},
      "productId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "quantity": {"type": "integer"},
      "status": {
        "type": "string",
        "enum": ["requested", "fulfilled", "rejected", "cancelled"],
      },
      "version": {"type": "integer"},
      "fulfilledBy": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "createdAt": {"type": "string", "format": "date-time"},
      "resolvedAt": {
        "anyOf": [
          {"type": "string", "format": "date-time"},
          {"type": "null"},
        ],
      },
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "userId",
      "rewardId",
      "title",
      "cost",
      "productId",
      "quantity",
      "status",
      "version",
      "fulfilledBy",
      "createdAt",
      "resolvedAt",
    ],
    "additionalProperties": false,
  },
  "OrderLine": {
    "type": "object",
    "properties": {
      "productId": {"type": "string", "format": "uuid"},
      "quantity": {"type": "integer"},
    },
    "required": ["productId", "quantity"],
    "additionalProperties": false,
  },
  "FulfillmentLine": {
    "type": "object",
    "properties": {
      "cancelled": {"type": "integer"},
      "productId": {"type": "string", "format": "uuid"},
      "ordered": {"type": "integer"},
      "received": {"type": "integer"},
      "inTransit": {"type": "integer"},
      "remainingToDispatch": {"type": "integer"},
      "remainingToReceive": {"type": "integer"},
    },
    "required": [
      "productId",
      "ordered",
      "received",
      "inTransit",
      "remainingToDispatch",
      "remainingToReceive",
    ],
    "additionalProperties": false,
  },
  "Order": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "status": {"type": "string"},
      "lines": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/OrderLine"},
      },
      "createdBy": {"type": "string", "format": "uuid"},
      "version": {"type": "integer"},
      "createdAt": {"type": "string", "format": "date-time"},
      "fulfillment": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/FulfillmentLine"},
      },
      "storeName": {"type": "string"},
      "openIssues": {"type": "integer"},
      "requestedLines": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/OrderLine"},
      },
      "cancelledLines": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/OrderLine"},
      },
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "status",
      "lines",
      "createdBy",
      "version",
      "createdAt",
    ],
    "additionalProperties": false,
  },
  "OrderFulfillment": {
    "type": "object",
    "properties": {
      "orderId": {"type": "string", "format": "uuid"},
      "version": {"type": "integer"},
      "status": {"type": "string"},
      "lines": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/FulfillmentLine"},
      },
    },
    "required": ["orderId", "version", "status", "lines"],
    "additionalProperties": false,
  },
  "Supply": {
    "type": "object",
    "properties": {
      "productId": {"type": "string", "format": "uuid"},
      "quantity": {"type": "integer"},
    },
    "required": ["productId", "quantity"],
    "additionalProperties": false,
  },
  "Delivery": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "orderId": {"type": "string", "format": "uuid"},
      "lines": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/OrderLine"},
      },
      "status": {"type": "string"},
      "version": {"type": "integer"},
      "dispatchedAt": {"type": "string", "format": "date-time"},
      "receivedAt": {
        "anyOf": [
          {"type": "string", "format": "date-time"},
          {"type": "null"},
        ],
      },
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "orderId",
      "lines",
      "status",
      "version",
      "dispatchedAt",
      "receivedAt",
    ],
    "additionalProperties": false,
  },
  "ReceiptLine": {
    "type": "object",
    "properties": {
      "productId": {"type": "string", "format": "uuid"},
      "batch": {"type": "string"},
      "expiry": {"type": "string"},
      "quantity": {"type": "integer"},
      "condition": {
        "type": "string",
        "enum": ["sellable", "damaged", "refused"],
      },
    },
    "required": ["productId", "batch", "expiry", "quantity"],
    "additionalProperties": false,
  },
  "DeliveryDifference": {
    "type": "object",
    "properties": {
      "productId": {"type": "string", "format": "uuid"},
      "expected": {"type": "integer"},
      "actual": {"type": "integer"},
      "damaged": {"type": "integer"},
      "refused": {"type": "integer"},
      "surplus": {"type": "integer"},
    },
    "required": ["productId", "expected", "actual"],
    "additionalProperties": false,
  },
  "DeliveryDifferences": {
    "type": "object",
    "properties": {
      "lines": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/DeliveryDifference"},
      },
      "note": {"type": "string"},
    },
    "required": ["lines", "note"],
    "additionalProperties": false,
  },
  "DeliveryReceipt": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "deliveryId": {"type": "string", "format": "uuid"},
      "lines": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/ReceiptLine"},
      },
      "differences": {"\$ref": "#/components/schemas/DeliveryDifferences"},
      "actorId": {"type": "string", "format": "uuid"},
      "operationId": {"type": "string", "format": "uuid"},
      "createdAt": {"type": "string", "format": "date-time"},
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "deliveryId",
      "lines",
      "differences",
      "actorId",
      "operationId",
      "createdAt",
    ],
    "additionalProperties": false,
  },
  "Alert": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "productId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "kind": {"type": "string"},
      "key": {"type": "string"},
      "message": {"type": "string"},
      "active": {"type": "boolean"},
      "createdAt": {"type": "string", "format": "date-time"},
      "resolvedAt": {
        "anyOf": [
          {"type": "string", "format": "date-time"},
          {"type": "null"},
        ],
      },
      "storeName": {"type": "string"},
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "productId",
      "kind",
      "key",
      "message",
      "active",
      "createdAt",
      "resolvedAt",
    ],
    "additionalProperties": false,
  },
  "Change": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "cursor": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "entity": {"type": "string"},
      "entityId": {"type": "string"},
      "deleted": {"type": "boolean"},
      "createdAt": {"type": "string", "format": "date-time"},
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "cursor",
      "entity",
      "entityId",
      "deleted",
      "createdAt",
    ],
    "additionalProperties": false,
  },
  "ChangePage": {
    "type": "object",
    "properties": {
      "changes": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/Change"},
      },
      "cursor": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "hasMore": {"type": "boolean"},
    },
    "required": ["changes", "cursor", "hasMore"],
    "additionalProperties": false,
  },
  "AuditEntry": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "storeId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "actorId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "action": {"type": "string"},
      "targetId": {"type": "string"},
      "operationId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "details": {"\$ref": "#/components/schemas/JsonValue"},
      "createdAt": {"type": "string", "format": "date-time"},
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "actorId",
      "action",
      "targetId",
      "operationId",
      "details",
      "createdAt",
    ],
    "additionalProperties": false,
  },
  "NotificationInbox": {
    "type": "object",
    "properties": {
      "items": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/Notification"},
      },
      "unreadCount": {"type": "integer"},
      "accessKey": {"type": "string"},
      "nextCursor": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
    },
    "required": ["items", "unreadCount", "accessKey", "nextCursor"],
    "additionalProperties": false,
  },
  "Notification": {
    "type": "object",
    "properties": {
      "targetType": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
      "targetId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "kind": {
        "enum": ["operational", "announcement"],
        "type": "string",
      },
      "audience": {
        "enum": ["managers", "all", "salespeople"],
        "type": "string",
      },
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "storeId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "userId": {"type": "string", "format": "uuid"},
      "eventKey": {"type": "string"},
      "title": {"type": "string"},
      "body": {"type": "string"},
      "readAt": {
        "anyOf": [
          {"type": "string", "format": "date-time"},
          {"type": "null"},
        ],
      },
      "createdAt": {"type": "string", "format": "date-time"},
    },
    "required": [
      "kind",
      "audience",
      "id",
      "organizationId",
      "storeId",
      "userId",
      "eventKey",
      "title",
      "body",
      "readAt",
      "createdAt",
    ],
    "additionalProperties": false,
  },
  "Device": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "userId": {"type": "string", "format": "uuid"},
      "sessionId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "token": {"type": "string"},
      "platform": {"type": "string"},
      "updatedAt": {"type": "string", "format": "date-time"},
    },
    "required": ["id", "userId", "sessionId", "token", "platform", "updatedAt"],
    "additionalProperties": false,
  },
  "AnnouncementResult": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "recipients": {"type": "integer"},
    },
    "required": ["id", "recipients"],
    "additionalProperties": false,
  },
  "TrainingContent": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "title": {"type": "string"},
      "body": {"type": "string"},
      "type": {
        "type": "string",
        "enum": ["article", "video"],
      },
      "mediaId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "productIds": {
        "type": "array",
        "items": {"type": "string", "format": "uuid"},
      },
      "status": {
        "type": "string",
        "enum": ["draft", "published", "archived"],
      },
      "version": {"type": "integer"},
      "authorId": {"type": "string", "format": "uuid"},
      "updatedAt": {"type": "string", "format": "date-time"},
    },
    "required": [
      "id",
      "title",
      "body",
      "type",
      "mediaId",
      "productIds",
      "status",
      "version",
      "authorId",
      "updatedAt",
    ],
    "additionalProperties": false,
  },
  "UploadStarted": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "status": {"type": "string"},
      "received": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "size": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "expectedSha256": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
    },
    "required": ["id", "status", "received", "size", "expectedSha256"],
    "additionalProperties": false,
  },
  "UploadStatus": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "status": {"type": "string"},
      "received": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "size": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "expectedSha256": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
      "sha256": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
      "processedSize": {
        "anyOf": [
          {"type": "string", "pattern": "^-?[0-9]+\$"},
          {"type": "null"},
        ],
      },
    },
    "required": [
      "id",
      "status",
      "received",
      "size",
      "expectedSha256",
      "sha256",
      "processedSize",
    ],
    "additionalProperties": false,
  },
  "UploadChunkResult": {
    "type": "object",
    "properties": {
      "received": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "status": {"type": "string"},
    },
    "required": ["received", "status"],
    "additionalProperties": false,
  },
  "MediaMetadata": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "mime": {"type": "string"},
      "size": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "sha256": {"type": "string"},
    },
    "required": ["id", "mime", "size", "sha256"],
    "additionalProperties": false,
  },
  "Onboarding": {
    "type": "object",
    "properties": {
      "profile": {"type": "boolean"},
      "team": {"type": "boolean"},
      "stock": {"type": "boolean"},
      "products": {"type": "boolean"},
      "workingAlone": {"type": "boolean"},
      "noOpeningStock": {"type": "boolean"},
      "carriedCount": {"type": "integer"},
      "incompleteProducts": {
        "type": "array",
        "items": {"type": "string", "format": "uuid"},
      },
      "completedCount": {"type": "integer"},
      "complete": {"type": "boolean"},
    },
    "required": [
      "profile",
      "team",
      "stock",
      "products",
      "workingAlone",
      "noOpeningStock",
      "carriedCount",
      "incompleteProducts",
      "completedCount",
      "complete",
    ],
    "additionalProperties": false,
  },
  "OnboardingResult": {
    "type": "object",
    "properties": {
      "store": {"\$ref": "#/components/schemas/Store"},
      "onboarding": {"\$ref": "#/components/schemas/Onboarding"},
    },
    "required": ["store", "onboarding"],
    "additionalProperties": false,
  },
  "RankingScore": {
    "type": "object",
    "properties": {
      "userId": {"type": "string", "format": "uuid"},
      "name": {"type": "string"},
      "score": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "rank": {"type": "string", "pattern": "^-?[0-9]+\$"},
    },
    "required": ["userId", "name", "score", "rank"],
    "additionalProperties": false,
  },
  "Ranking": {
    "type": "object",
    "properties": {
      "month": {"type": "string", "pattern": "^[0-9]{4}-[0-9]{2}\$"},
      "scores": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/RankingScore"},
      },
    },
    "required": ["month", "scores"],
    "additionalProperties": false,
  },
  "AdminOverview": {
    "type": "object",
    "properties": {
      "storeCount": {"type": "integer"},
      "staffCount": {"type": "integer"},
      "orders": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/Order"},
      },
      "alerts": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/Alert"},
      },
    },
    "required": ["storeCount", "staffCount", "orders", "alerts"],
    "additionalProperties": false,
  },
  "ReportOverview": {
    "type": "object",
    "properties": {
      "stores": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/StoreAccess"},
      },
      "totalStores": {"type": "integer"},
      "organizations": {"type": "integer"},
      "staff": {"type": "integer"},
    },
    "required": ["stores", "totalStores", "organizations", "staff"],
    "additionalProperties": false,
  },
  "ApiError": {
    "type": "object",
    "properties": {
      "code": {"type": "string"},
      "message": {"type": "string"},
      "correlationId": {"type": "string"},
      "fields": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/ApiErrorFieldsItem"},
      },
    },
    "required": ["code", "message"],
    "additionalProperties": false,
  },
  "AffectedVersion": {
    "type": "object",
    "properties": {
      "resource": {
        "type": "string",
        "enum": ["lots", "sales", "orders", "deliveries", "claims"],
      },
      "id": {"type": "string", "format": "uuid"},
      "version": {"type": "integer"},
    },
    "required": ["resource", "id", "version"],
    "additionalProperties": false,
  },
  "CommandOutcome": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "version": {"type": "integer"},
      "orderVersion": {"type": "integer"},
      "status": {"type": "string"},
      "total": {"\$ref": "#/components/schemas/Money"},
      "points": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "differences": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/DeliveryDifference"},
      },
    },
    "required": ["id"],
    "additionalProperties": false,
  },
  "SyncResult": {
    "oneOf": [
      {"\$ref": "#/components/schemas/SyncResultAccepted"},
      {"\$ref": "#/components/schemas/SyncResultConflict"},
      {"\$ref": "#/components/schemas/SyncResultRejected"},
      {"\$ref": "#/components/schemas/SyncResultBlocked"},
      {"\$ref": "#/components/schemas/SyncResultRetryable"},
    ],
    "discriminator": {"propertyName": "status"},
  },
  "OperationStatus": {
    "oneOf": [
      {"\$ref": "#/components/schemas/SyncResult"},
      {"\$ref": "#/components/schemas/OperationStatusUnknown"},
    ],
  },
  "SyncResponse": {
    "type": "object",
    "properties": {
      "results": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/SyncResult"},
      },
    },
    "required": ["results"],
    "additionalProperties": false,
  },
  "StatusResponse": {
    "type": "object",
    "properties": {
      "results": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/OperationStatus"},
      },
    },
    "required": ["results"],
    "additionalProperties": false,
  },
  "CollectionItem": {
    "anyOf": [
      {"\$ref": "#/components/schemas/InventoryLot"},
      {"\$ref": "#/components/schemas/StoreProduct"},
      {"\$ref": "#/components/schemas/Product"},
      {"\$ref": "#/components/schemas/Sale"},
      {"\$ref": "#/components/schemas/PointsEntry"},
      {"\$ref": "#/components/schemas/AuditEntry"},
    ],
  },
  "HistoryItem": {
    "anyOf": [
      {"\$ref": "#/components/schemas/Sale"},
      {"\$ref": "#/components/schemas/PointsEntry"},
      {"\$ref": "#/components/schemas/StockMovement"},
      {"\$ref": "#/components/schemas/AuditEntry"},
    ],
  },
  "HistoryPage": {
    "type": "object",
    "properties": {
      "items": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/HistoryItem"},
      },
      "people": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/Person"},
      },
      "nextCursor": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
    },
    "required": ["items", "people", "nextCursor"],
    "additionalProperties": false,
  },
  "SnapshotPage": {
    "oneOf": [
      {"\$ref": "#/components/schemas/SnapshotPageLots"},
      {"\$ref": "#/components/schemas/SnapshotPageProducts"},
      {"\$ref": "#/components/schemas/SnapshotPageConfig"},
      {"\$ref": "#/components/schemas/SnapshotPageRewards"},
      {"\$ref": "#/components/schemas/SnapshotPageClaims"},
      {"\$ref": "#/components/schemas/SnapshotPageOrders"},
      {"\$ref": "#/components/schemas/SnapshotPageDeliveries"},
    ],
    "discriminator": {"propertyName": "resource"},
  },
  "Snapshot": {
    "type": "object",
    "properties": {
      "syncProtocol": {
        "type": "integer",
        "enum": [2, 3],
      },
      "snapshotPages": {"\$ref": "#/components/schemas/SnapshotSnapshotPages"},
      "snapshotExpiresAt": {"type": "string", "format": "date-time"},
      "appliedOperationIds": {
        "type": "array",
        "items": {"type": "string", "format": "uuid"},
      },
      "catalogRevision": {"type": "string"},
      "mode": {
        "type": "string",
        "enum": ["delta", "snapshot"],
      },
      "mergeResources": {
        "type": "array",
        "items": {"type": "string"},
      },
      "summary": {"\$ref": "#/components/schemas/SnapshotSummary"},
      "store": {"\$ref": "#/components/schemas/Store"},
      "onboarding": {
        "anyOf": [
          {"\$ref": "#/components/schemas/Onboarding"},
          {"type": "null"},
        ],
      },
      "permissions": {
        "type": "array",
        "items": {
          "type": "string",
          "enum": ["sell", "receive", "manage"],
        },
      },
      "products": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/Product"},
      },
      "config": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/StoreProduct"},
      },
      "lots": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/InventoryLot"},
      },
      "sales": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/Sale"},
      },
      "alerts": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/Alert"},
      },
      "points": {"\$ref": "#/components/schemas/PointsAccount"},
      "rewards": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/Reward"},
      },
      "claims": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/RewardClaim"},
      },
      "orders": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/Order"},
      },
      "outstandingSupply": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/Supply"},
      },
      "deliveries": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/Delivery"},
      },
      "team": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/TeamMember"},
      },
      "invitations": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/InvitationSummary"},
      },
      "cursor": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "serverTime": {"type": "string", "format": "date-time"},
      "pagination": {"\$ref": "#/components/schemas/SnapshotPagination"},
    },
    "required": [
      "syncProtocol",
      "snapshotPages",
      "snapshotExpiresAt",
      "appliedOperationIds",
      "catalogRevision",
      "mode",
      "mergeResources",
      "summary",
      "store",
      "onboarding",
      "permissions",
      "products",
      "config",
      "lots",
      "sales",
      "alerts",
      "points",
      "rewards",
      "claims",
      "orders",
      "outstandingSupply",
      "deliveries",
      "team",
      "invitations",
      "cursor",
      "serverTime",
      "pagination",
    ],
    "additionalProperties": false,
  },
  "AlertDetails": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "productId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "kind": {"type": "string"},
      "key": {"type": "string"},
      "message": {"type": "string"},
      "active": {"type": "boolean"},
      "createdAt": {"type": "string", "format": "date-time"},
      "resolvedAt": {
        "anyOf": [
          {"type": "string", "format": "date-time"},
          {"type": "null"},
        ],
      },
      "storeName": {"type": "string"},
      "groupName": {"type": "string"},
      "orderId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "productId",
      "kind",
      "key",
      "message",
      "active",
      "createdAt",
      "resolvedAt",
      "storeName",
      "groupName",
      "orderId",
    ],
    "additionalProperties": false,
  },
  "AttentionPage": {
    "type": "object",
    "properties": {
      "items": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/AttentionPageItemsItem"},
      },
      "nextCursor": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
    },
    "required": ["items", "nextCursor"],
    "additionalProperties": false,
  },
  "ReportExport": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "status": {
        "type": "string",
        "enum": ["pending", "processing", "ready", "failed"],
      },
      "rows": {"type": "integer"},
      "error": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
      "createdAt": {"type": "string", "format": "date-time"},
      "expiresAt": {"type": "string", "format": "date-time"},
    },
    "required": ["id", "status", "rows", "error", "createdAt", "expiresAt"],
    "additionalProperties": false,
  },
  "DashboardSale": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "sellerId": {"type": "string", "format": "uuid"},
      "day": {"type": "string"},
      "occurredAt": {"type": "string", "format": "date-time"},
      "version": {"type": "integer"},
      "netMillimes": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "netUnits": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "storeName": {"type": "string"},
      "sellerName": {"type": "string"},
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "sellerId",
      "day",
      "occurredAt",
      "version",
      "netMillimes",
      "netUnits",
      "storeName",
      "sellerName",
    ],
    "additionalProperties": false,
  },
  "DashboardSalePage": {
    "type": "object",
    "properties": {
      "items": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/DashboardSale"},
      },
      "nextCursor": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
    },
    "required": ["items", "nextCursor"],
    "additionalProperties": false,
  },
  "Group": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "name": {"type": "string"},
      "createdAt": {"type": "string", "format": "date-time"},
      "imageId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "phone": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
      "version": {"type": "integer"},
      "status": {"type": "string"},
      "statusReason": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
      "statusChangedAt": {
        "anyOf": [
          {"type": "string", "format": "date-time"},
          {"type": "null"},
        ],
      },
      "statusChangedBy": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
    },
    "required": ["id", "name", "createdAt", "imageId", "phone", "version"],
    "additionalProperties": false,
  },
  "GroupAccess": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "name": {"type": "string"},
      "createdAt": {"type": "string", "format": "date-time"},
      "imageId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "phone": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
      "version": {"type": "integer"},
      "status": {"type": "string"},
      "statusReason": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
      "statusChangedAt": {
        "anyOf": [
          {"type": "string", "format": "date-time"},
          {"type": "null"},
        ],
      },
      "statusChangedBy": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "canManage": {"type": "boolean"},
      "storeCount": {"type": "integer"},
    },
    "required": [
      "id",
      "name",
      "createdAt",
      "imageId",
      "phone",
      "version",
      "canManage",
      "storeCount",
    ],
    "additionalProperties": false,
  },
  "GroupPage": {
    "type": "object",
    "properties": {
      "items": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/GroupAccess"},
      },
      "nextCursor": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "creationGrants": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/GroupPageCreationGrantsItem"},
      },
    },
    "required": ["items", "nextCursor", "creationGrants"],
    "additionalProperties": false,
  },
  "GroupTeam": {
    "type": "object",
    "properties": {
      "members": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/GroupTeamMembersItem"},
      },
      "invitations": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/GroupTeamInvitationsItem"},
      },
    },
    "required": ["members", "invitations"],
    "additionalProperties": false,
  },
  "ProductPage": {
    "type": "object",
    "properties": {
      "items": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/Product"},
      },
      "nextCursor": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
    },
    "required": ["items", "nextCursor"],
    "additionalProperties": false,
  },
  "Dashboard": {
    "type": "object",
    "properties": {
      "scope": {
        "type": "string",
        "enum": ["network", "group", "store", "personal"],
      },
      "organizationId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "storeId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "from": {"type": "string"},
      "to": {"type": "string"},
      "generatedAt": {"type": "string", "format": "date-time"},
      "netMillimes": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "netUnits": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "saleCount": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "groupCount": {"type": "integer"},
      "storeCount": {"type": "integer"},
      "series": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/DashboardSeriesItem"},
      },
      "comparisons": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/DashboardComparisonsItem"},
      },
      "products": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/DashboardProductsItem"},
      },
      "recentSales": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/DashboardRecentSalesItem"},
      },
      "ranking": {
        "anyOf": [
          {"\$ref": "#/components/schemas/DashboardRanking"},
          {"type": "null"},
        ],
      },
      "current": {"\$ref": "#/components/schemas/DashboardCurrent"},
      "alerts": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/DashboardAlertsItem"},
      },
    },
    "required": [
      "scope",
      "organizationId",
      "storeId",
      "from",
      "to",
      "generatedAt",
      "netMillimes",
      "netUnits",
      "saleCount",
      "groupCount",
      "storeCount",
      "series",
      "comparisons",
      "products",
      "recentSales",
      "ranking",
      "current",
      "alerts",
    ],
    "additionalProperties": false,
  },
  "DeliveryIssue": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "deliveryId": {"type": "string", "format": "uuid"},
      "orderId": {"type": "string", "format": "uuid"},
      "status": {"type": "string"},
      "reason": {"type": "string"},
      "heldLines": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/DeliveryIssueHeldLinesItem"},
      },
      "resolution": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
      "resolutionNote": {
        "anyOf": [
          {"type": "string"},
          {"type": "null"},
        ],
      },
      "reportedBy": {"type": "string", "format": "uuid"},
      "resolvedBy": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "createdAt": {"type": "string", "format": "date-time"},
      "resolvedAt": {
        "anyOf": [
          {"type": "string", "format": "date-time"},
          {"type": "null"},
        ],
      },
      "version": {"type": "integer"},
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "deliveryId",
      "orderId",
      "status",
      "reason",
      "heldLines",
      "resolution",
      "resolutionNote",
      "reportedBy",
      "resolvedBy",
      "createdAt",
      "resolvedAt",
      "version",
    ],
    "additionalProperties": false,
  },
  "ScopedOrder": {
    "type": "object",
    "properties": {
      "requestedLines": {
        "type": "array",
        "items": {
          "\$ref": "#/components/schemas/ScopedOrderRequestedLinesItem",
        },
      },
      "cancelledLines": {
        "type": "array",
        "items": {
          "\$ref": "#/components/schemas/ScopedOrderCancelledLinesItem",
        },
      },
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "createdBy": {"type": "string", "format": "uuid"},
      "lines": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/ScopedOrderLinesItem"},
      },
      "status": {"type": "string"},
      "version": {"type": "integer"},
      "createdAt": {"type": "string", "format": "date-time"},
      "storeName": {"type": "string"},
      "groupName": {"type": "string"},
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "createdBy",
      "lines",
      "status",
      "version",
      "createdAt",
      "storeName",
      "groupName",
    ],
    "additionalProperties": false,
  },
  "OrderPage": {
    "type": "object",
    "properties": {
      "items": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/ScopedOrder"},
      },
      "nextCursor": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
    },
    "required": ["items", "nextCursor"],
    "additionalProperties": false,
  },
  "ScopedOrderDetails": {
    "type": "object",
    "properties": {
      "order": {"\$ref": "#/components/schemas/ScopedOrder"},
      "issues": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/DeliveryIssue"},
      },
      "history": {
        "type": "array",
        "items": {
          "\$ref": "#/components/schemas/ScopedOrderDetailsHistoryItem",
        },
      },
      "deliveries": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/Delivery"},
      },
      "receipts": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/DeliveryReceipt"},
      },
      "fulfillment": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/FulfillmentLine"},
      },
    },
    "required": ["order", "deliveries"],
    "additionalProperties": false,
  },
  "InvitationRecord": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "email": {"type": "string"},
      "organizationId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "kind": {"type": "string"},
      "storeIds": {
        "type": "array",
        "items": {"type": "string", "format": "uuid"},
      },
      "status": {
        "type": "string",
        "enum": [
          "pending",
          "expired",
          "accepted",
          "revoked",
          "replaced",
          "closed",
          "archived",
        ],
      },
      "createdAt": {
        "anyOf": [
          {"type": "string", "format": "date-time"},
          {"type": "null"},
        ],
      },
      "expiresAt": {"type": "string", "format": "date-time"},
      "acceptedAt": {
        "anyOf": [
          {"type": "string", "format": "date-time"},
          {"type": "null"},
        ],
      },
      "version": {"type": "integer"},
    },
    "required": [
      "id",
      "email",
      "organizationId",
      "kind",
      "storeIds",
      "status",
      "createdAt",
      "expiresAt",
      "acceptedAt",
      "version",
    ],
    "additionalProperties": false,
  },
  "InvitationPage": {
    "type": "object",
    "properties": {
      "items": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/InvitationRecord"},
      },
      "nextCursor": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
    },
    "required": ["items", "nextCursor"],
    "additionalProperties": false,
  },
  "Command": {
    "oneOf": [
      {"\$ref": "#/components/schemas/CommandSaleCreate"},
      {"\$ref": "#/components/schemas/CommandSaleCorrect"},
      {"\$ref": "#/components/schemas/CommandSaleReturn"},
      {"\$ref": "#/components/schemas/CommandStockReceive"},
      {"\$ref": "#/components/schemas/CommandStockAdjust"},
      {"\$ref": "#/components/schemas/CommandStockDamage"},
      {"\$ref": "#/components/schemas/CommandOrderCreate"},
      {"\$ref": "#/components/schemas/CommandOrderPrepare"},
      {"\$ref": "#/components/schemas/CommandOrderAmend"},
      {"\$ref": "#/components/schemas/CommandOrderCancel"},
      {"\$ref": "#/components/schemas/CommandDeliveryReport"},
      {"\$ref": "#/components/schemas/CommandDeliveryResolve"},
      {"\$ref": "#/components/schemas/CommandDeliveryDispatch"},
      {"\$ref": "#/components/schemas/CommandDeliveryReceive"},
      {"\$ref": "#/components/schemas/CommandRewardRequest"},
      {"\$ref": "#/components/schemas/CommandRewardResolve"},
    ],
  },
  "SyncOperation": {
    "type": "object",
    "properties": {
      "operationId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "storeId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "organizationId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "payloadVersion": {
        "type": "integer",
        "enum": [1, 2],
      },
      "dependencies": {
        "maxItems": 5000,
        "type": "array",
        "items": {
          "type": "string",
          "format": "uuid",
          "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
        },
      },
      "expectedVersion": {
        "type": "integer",
        "minimum": 1,
        "maximum": 9007199254740991,
      },
      "command": {"\$ref": "#/components/schemas/Command"},
    },
    "required": [
      "operationId",
      "storeId",
      "organizationId",
      "payloadVersion",
      "command",
    ],
    "additionalProperties": false,
  },
  "SyncBatch": {
    "type": "object",
    "properties": {
      "operations": {
        "minItems": 1,
        "maxItems": 50,
        "type": "array",
        "items": {"\$ref": "#/components/schemas/SyncOperation"},
      },
    },
    "required": ["operations"],
    "additionalProperties": false,
  },
  "CatalogImportResult": {
    "anyOf": [
      {"\$ref": "#/components/schemas/CatalogImportResultTrue"},
      {"\$ref": "#/components/schemas/Count"},
    ],
  },
  "InvitationManagementListResponse": {
    "\$ref": "#/components/schemas/InvitationPage",
  },
  "IdentityInviteResponse": {"\$ref": "#/components/schemas/Invitation"},
  "IdentityInviteRequest": {
    "type": "object",
    "properties": {
      "email": {
        "type": "string",
        "format": "email",
        "pattern": "^(?:[A-Za-z0-9_'+\\-]+\\.)*[A-Za-z0-9_'+\\-]*[A-Za-z0-9_+-]@(?:[A-Za-z0-9][A-Za-z0-9\\-]*\\.)+[A-Za-z]{2,}\$",
      },
      "kind": {
        "type": "string",
        "enum": ["new_group", "responsible", "salesperson"],
      },
      "storeIds": {
        "maxItems": 1,
        "type": "array",
        "items": {
          "type": "string",
          "format": "uuid",
          "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
        },
      },
      "organizationId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "organizationName": {"type": "string", "minLength": 2, "maxLength": 120},
      "storeId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "permissions": {
        "default": ["sell", "receive"],
        "minItems": 1,
        "type": "array",
        "items": {
          "type": "string",
          "enum": ["sell", "receive", "manage"],
        },
      },
    },
    "required": ["email"],
  },
  "InvitationManagementActionResponse": {
    "type": "object",
    "properties": {
      "ok": {"const": true, "type": "boolean"},
      "id": {"type": "string", "format": "uuid"},
    },
    "required": ["ok", "id"],
    "additionalProperties": false,
  },
  "InvitationManagementActionRequest": {
    "type": "object",
    "properties": {
      "action": {
        "type": "string",
        "enum": ["resend", "revoke", "archive"],
      },
      "expectedVersion": {
        "type": "integer",
        "exclusiveMinimum": 0,
        "maximum": 9007199254740991,
      },
      "operationId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
    },
    "required": ["action", "expectedVersion", "operationId"],
    "additionalProperties": false,
  },
  "ExportCreateResponse": {"\$ref": "#/components/schemas/ReportExport"},
  "ExportCreateRequest": {
    "type": "object",
    "properties": {
      "id": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "query": {"\$ref": "#/components/schemas/ExportCreateRequestQuery"},
    },
    "required": ["id", "query"],
    "additionalProperties": false,
  },
  "ExportGetResponse": {"\$ref": "#/components/schemas/ReportExport"},
  "ExportFileResponse": {"type": "string"},
  "DashboardGetResponse": {"\$ref": "#/components/schemas/Dashboard"},
  "DashboardOrdersResponse": {"\$ref": "#/components/schemas/OrderPage"},
  "DashboardAttentionResponse": {"\$ref": "#/components/schemas/AttentionPage"},
  "DashboardAlertResponse": {"\$ref": "#/components/schemas/AlertDetails"},
  "DashboardSalesResponse": {"\$ref": "#/components/schemas/DashboardSalePage"},
  "DashboardOrderResponse": {
    "\$ref": "#/components/schemas/ScopedOrderDetails",
  },
  "GroupImpactResponse": {
    "type": "object",
    "properties": {
      "orders": {"type": "integer"},
      "deliveries": {"type": "integer"},
      "rewards": {"type": "integer"},
      "issues": {"type": "integer"},
      "stockLots": {"type": "integer"},
    },
    "required": ["orders", "deliveries", "rewards", "issues", "stockLots"],
    "additionalProperties": false,
  },
  "GroupLifecycleResponse": {"\$ref": "#/components/schemas/Ok"},
  "GroupLifecycleRequest": {
    "type": "object",
    "properties": {
      "operationId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "expectedVersion": {
        "type": "integer",
        "exclusiveMinimum": 0,
        "maximum": 9007199254740991,
      },
      "status": {
        "type": "string",
        "enum": ["active", "suspended", "archived"],
      },
      "reason": {"type": "string", "minLength": 3, "maxLength": 500},
    },
    "required": ["operationId", "expectedVersion", "status", "reason"],
    "additionalProperties": false,
  },
  "GroupListResponse": {"\$ref": "#/components/schemas/GroupPage"},
  "GroupCreateResponse": {"\$ref": "#/components/schemas/Group"},
  "GroupCreateRequest": {
    "type": "object",
    "properties": {
      "grantId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "operationId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "name": {"type": "string", "minLength": 2, "maxLength": 120},
      "phone": {"type": "string", "maxLength": 30},
    },
    "required": ["grantId", "operationId", "name"],
    "additionalProperties": false,
  },
  "GroupUpdateResponse": {"\$ref": "#/components/schemas/Group"},
  "GroupUpdateRequest": {
    "type": "object",
    "properties": {
      "name": {"type": "string", "minLength": 2, "maxLength": 120},
      "phone": {
        "anyOf": [
          {"type": "string", "maxLength": 30},
          {"type": "null"},
        ],
      },
      "imageId": {
        "anyOf": [
          {
            "type": "string",
            "format": "uuid",
            "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
          },
          {"type": "null"},
        ],
      },
      "expectedVersion": {
        "type": "integer",
        "exclusiveMinimum": 0,
        "maximum": 9007199254740991,
      },
    },
    "required": ["name", "expectedVersion"],
    "additionalProperties": false,
  },
  "GroupStoresResponse": {
    "type": "array",
    "items": {"\$ref": "#/components/schemas/StoreAccess"},
  },
  "GroupTeamResponse": {"\$ref": "#/components/schemas/GroupTeam"},
  "GroupMemberResponse": {"\$ref": "#/components/schemas/Ok"},
  "GroupMemberRequest": {
    "type": "object",
    "properties": {
      "active": {"type": "boolean"},
      "role": {
        "type": "string",
        "enum": ["responsible", "salesperson"],
      },
      "storeIds": {
        "default": [],
        "maxItems": 1,
        "type": "array",
        "items": {
          "type": "string",
          "format": "uuid",
          "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
        },
      },
    },
    "required": ["active", "role"],
    "additionalProperties": false,
  },
  "AdminOverviewResponse": {"\$ref": "#/components/schemas/AdminOverview"},
  "HealthHealthResponse": {"\$ref": "#/components/schemas/Health"},
  "IdentityLoginResponse": {"\$ref": "#/components/schemas/LoginResponse"},
  "IdentityLoginRequest": {
    "type": "object",
    "properties": {
      "email": {
        "type": "string",
        "format": "email",
        "pattern": "^(?:[A-Za-z0-9_'+\\-]+\\.)*[A-Za-z0-9_'+\\-]*[A-Za-z0-9_+-]@(?:[A-Za-z0-9][A-Za-z0-9\\-]*\\.)+[A-Za-z]{2,}\$",
      },
      "password": {"type": "string", "minLength": 1, "maxLength": 128},
      "otp": {"type": "string"},
    },
    "required": ["email", "password"],
  },
  "IdentityMeResponse": {"\$ref": "#/components/schemas/User"},
  "IdentityLogoutResponse": {"\$ref": "#/components/schemas/Ok"},
  "IdentityActivateResponse": {"\$ref": "#/components/schemas/Activated"},
  "IdentityActivateRequest": {
    "type": "object",
    "properties": {
      "token": {"type": "string", "minLength": 32, "maxLength": 256},
      "name": {"type": "string", "minLength": 2, "maxLength": 120},
      "password": {"type": "string", "minLength": 12, "maxLength": 128},
    },
    "required": ["token", "name", "password"],
  },
  "IdentityForgotResponse": {"\$ref": "#/components/schemas/Message"},
  "IdentityForgotRequest": {
    "type": "object",
    "properties": {
      "email": {
        "type": "string",
        "format": "email",
        "pattern": "^(?:[A-Za-z0-9_'+\\-]+\\.)*[A-Za-z0-9_'+\\-]*[A-Za-z0-9_+-]@(?:[A-Za-z0-9][A-Za-z0-9\\-]*\\.)+[A-Za-z]{2,}\$",
      },
    },
    "required": ["email"],
  },
  "IdentityResetResponse": {"\$ref": "#/components/schemas/Ok"},
  "IdentityResetRequest": {
    "type": "object",
    "properties": {
      "token": {
        "type": "string",
        "pattern":
            "^(?:[A-Za-z0-9]{4}[- ]?[A-Za-z0-9]{4}|[A-Za-z0-9_-]{32,256})\$",
      },
      "password": {"type": "string", "minLength": 12, "maxLength": 128},
    },
    "required": ["token", "password"],
  },
  "WorkspaceOrganizationsResponse": {
    "type": "array",
    "items": {"\$ref": "#/components/schemas/Organization"},
  },
  "WorkspaceStoresResponse": {
    "type": "array",
    "items": {"\$ref": "#/components/schemas/StoreAccess"},
  },
  "WorkspaceCreateResponse": {"\$ref": "#/components/schemas/Store"},
  "WorkspaceCreateRequest": {
    "type": "object",
    "properties": {
      "organizationId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "name": {"type": "string", "minLength": 2, "maxLength": 120},
      "address": {"type": "string", "minLength": 3, "maxLength": 300},
      "city": {"type": "string", "minLength": 2, "maxLength": 120},
      "phone": {"type": "string", "maxLength": 30},
    },
    "required": ["organizationId", "name", "address", "city"],
    "additionalProperties": false,
  },
  "WorkspaceUpdateStoreResponse": {"\$ref": "#/components/schemas/Store"},
  "WorkspaceUpdateStoreRequest": {
    "type": "object",
    "properties": {
      "name": {"type": "string", "minLength": 2, "maxLength": 120},
      "address": {"type": "string", "minLength": 3, "maxLength": 300},
      "city": {"type": "string", "minLength": 2, "maxLength": 120},
      "phone": {
        "anyOf": [
          {"type": "string", "maxLength": 30},
          {"type": "null"},
        ],
      },
      "imageId": {
        "anyOf": [
          {
            "type": "string",
            "format": "uuid",
            "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
          },
          {"type": "null"},
        ],
      },
      "expectedVersion": {
        "type": "integer",
        "exclusiveMinimum": 0,
        "maximum": 9007199254740991,
      },
    },
    "required": ["name", "address", "city", "expectedVersion"],
    "additionalProperties": false,
  },
  "WorkspaceSnapshotResponse": {"\$ref": "#/components/schemas/Snapshot"},
  "WorkspaceSnapshotPageResponse": {
    "\$ref": "#/components/schemas/SnapshotPage",
  },
  "WorkspaceCollectionResponse": {
    "type": "array",
    "items": {"\$ref": "#/components/schemas/CollectionItem"},
  },
  "WorkspaceHistoryResponse": {"\$ref": "#/components/schemas/HistoryPage"},
  "WorkspaceFulfillmentResponse": {
    "\$ref": "#/components/schemas/OrderFulfillment",
  },
  "WorkspaceSaleResponse": {"\$ref": "#/components/schemas/SaleDetails"},
  "WorkspaceChangesResponse": {"\$ref": "#/components/schemas/ChangePage"},
  "WorkspaceRankingResponse": {"\$ref": "#/components/schemas/Ranking"},
  "WorkspaceConfigResponse": {"\$ref": "#/components/schemas/StoreProduct"},
  "WorkspaceConfigRequest": {
    "type": "object",
    "properties": {
      "priceMillimes": {"type": "string", "pattern": "^(0|[1-9]\\d{0,14})\$"},
      "threshold": {"type": "integer", "minimum": 0, "maximum": 1000000},
      "pointsPerUnit": {"type": "integer", "minimum": 0, "maximum": 100000},
      "zeroPointsConfirmed": {"type": "boolean"},
      "expectedVersion": {
        "type": "integer",
        "exclusiveMinimum": 0,
        "maximum": 9007199254740991,
      },
    },
    "required": ["priceMillimes", "threshold", "pointsPerUnit"],
    "additionalProperties": false,
  },
  "WorkspaceMemberResponse": {"\$ref": "#/components/schemas/Membership"},
  "WorkspaceMemberRequest": {
    "type": "object",
    "properties": {
      "active": {"type": "boolean"},
      "permissions": {
        "minItems": 1,
        "type": "array",
        "items": {
          "type": "string",
          "enum": ["sell", "receive", "manage"],
        },
      },
    },
    "required": ["active", "permissions"],
    "additionalProperties": false,
  },
  "WorkspaceOnboardingResponse": {
    "\$ref": "#/components/schemas/OnboardingResult",
  },
  "WorkspaceOnboardingRequest": {
    "type": "object",
    "properties": {
      "step": {"type": "integer", "minimum": 1, "maximum": 5},
      "workingAlone": {"type": "boolean"},
      "noOpeningStock": {"type": "boolean"},
      "expectedVersion": {
        "type": "integer",
        "exclusiveMinimum": 0,
        "maximum": 9007199254740991,
      },
    },
    "additionalProperties": false,
  },
  "WorkspaceRewardResponse": {"\$ref": "#/components/schemas/Reward"},
  "WorkspaceRewardRequest": {
    "type": "object",
    "properties": {
      "id": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "title": {"type": "string", "minLength": 2, "maxLength": 120},
      "description": {"default": "", "type": "string", "maxLength": 2000},
      "cost": {"type": "integer", "exclusiveMinimum": 0, "maximum": 100000000},
      "productId": {
        "anyOf": [
          {
            "type": "string",
            "format": "uuid",
            "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
          },
          {"type": "null"},
        ],
      },
      "imageId": {
        "anyOf": [
          {
            "type": "string",
            "format": "uuid",
            "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
          },
          {"type": "null"},
        ],
      },
      "quantity": {
        "default": 1,
        "type": "integer",
        "exclusiveMinimum": 0,
        "maximum": 1000000,
      },
      "active": {"default": true, "type": "boolean"},
      "expectedVersion": {
        "type": "integer",
        "exclusiveMinimum": 0,
        "maximum": 9007199254740991,
      },
    },
    "required": ["title", "cost"],
    "additionalProperties": false,
  },
  "CatalogListResponse": {"\$ref": "#/components/schemas/ProductPage"},
  "CatalogSaveResponse": {"\$ref": "#/components/schemas/Product"},
  "CatalogSaveRequest": {
    "type": "object",
    "properties": {
      "id": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "reference": {"type": "string", "minLength": 1, "maxLength": 80},
      "name": {"type": "string", "minLength": 2, "maxLength": 160},
      "imageId": {
        "anyOf": [
          {
            "type": "string",
            "format": "uuid",
            "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
          },
          {"type": "null"},
        ],
      },
      "barcode": {"type": "string", "minLength": 3, "maxLength": 80},
      "description": {"default": "", "type": "string", "maxLength": 5000},
      "category": {"type": "string", "maxLength": 100},
      "range": {"type": "string", "maxLength": 100},
      "packageSize": {"type": "string", "maxLength": 80},
      "instructions": {"type": "string", "maxLength": 5000},
      "ingredients": {"type": "string", "maxLength": 5000},
      "precautions": {"type": "string", "maxLength": 5000},
      "referencePriceMillimes": {
        "anyOf": [
          {"type": "string", "pattern": "^(0|[1-9]\\d{0,14})\$"},
          {"type": "null"},
        ],
      },
      "priceStatus": {
        "type": "string",
        "enum": ["missing", "verified", "sample"],
      },
      "sourceUrls": {
        "maxItems": 12,
        "type": "array",
        "items": {"type": "string", "maxLength": 2000, "format": "uri"},
      },
      "active": {"default": true, "type": "boolean"},
      "expectedVersion": {
        "type": "integer",
        "exclusiveMinimum": 0,
        "maximum": 9007199254740991,
      },
    },
    "required": ["reference", "name"],
    "additionalProperties": false,
  },
  "CatalogImportResponse": {
    "\$ref": "#/components/schemas/CatalogImportResult",
  },
  "CatalogImportRequest": {
    "type": "object",
    "properties": {
      "rows": {
        "minItems": 1,
        "maxItems": 1000,
        "type": "array",
        "items": {"\$ref": "#/components/schemas/CatalogImportRequestRowsItem"},
      },
      "commit": {"default": false, "type": "boolean"},
    },
    "required": ["rows"],
    "additionalProperties": false,
  },
  "OperationsStatusResponse": {"\$ref": "#/components/schemas/StatusResponse"},
  "OperationsStatusRequest": {"\$ref": "#/components/schemas/SyncBatch"},
  "OperationsPushResponse": {"\$ref": "#/components/schemas/SyncResponse"},
  "OperationsPushRequest": {"\$ref": "#/components/schemas/SyncBatch"},
  "NotificationsListResponse": {
    "type": "array",
    "items": {"\$ref": "#/components/schemas/Notification"},
  },
  "NotificationsInboxResponse": {
    "\$ref": "#/components/schemas/NotificationInbox",
  },
  "NotificationsGetResponse": {"\$ref": "#/components/schemas/Notification"},
  "NotificationsReadResponse": {"\$ref": "#/components/schemas/Count"},
  "NotificationsDeviceResponse": {"\$ref": "#/components/schemas/Device"},
  "NotificationsDeviceRequest": {
    "type": "object",
    "properties": {
      "token": {"type": "string", "minLength": 20, "maxLength": 4096},
      "platform": {
        "type": "string",
        "enum": ["android", "ios"],
      },
    },
    "required": ["token", "platform"],
  },
  "NotificationsRemoveDeviceResponse": {"\$ref": "#/components/schemas/Count"},
  "NotificationsRemoveDeviceRequest": {
    "type": "object",
    "properties": {
      "token": {"type": "string", "minLength": 20, "maxLength": 4096},
    },
    "required": ["token"],
  },
  "NotificationsAnnounceResponse": {
    "\$ref": "#/components/schemas/AnnouncementResult",
  },
  "NotificationsAnnounceRequest": {
    "type": "object",
    "properties": {
      "id": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "title": {"type": "string", "minLength": 2, "maxLength": 120},
      "body": {"type": "string", "minLength": 2, "maxLength": 2000},
      "audience": {
        "type": "string",
        "enum": ["all", "salespeople"],
      },
    },
    "required": ["id", "title", "body", "audience"],
    "additionalProperties": false,
  },
  "TrainingListResponse": {
    "type": "array",
    "items": {"\$ref": "#/components/schemas/TrainingContent"},
  },
  "TrainingSaveResponse": {"\$ref": "#/components/schemas/TrainingContent"},
  "TrainingSaveRequest": {
    "type": "object",
    "properties": {
      "id": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "submissionId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "title": {"type": "string", "minLength": 3, "maxLength": 200},
      "body": {"type": "string", "maxLength": 100000},
      "type": {
        "type": "string",
        "enum": ["article", "video"],
      },
      "mediaId": {
        "anyOf": [
          {
            "type": "string",
            "format": "uuid",
            "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
          },
          {"type": "null"},
        ],
      },
      "productIds": {
        "default": [],
        "maxItems": 100,
        "type": "array",
        "items": {
          "type": "string",
          "format": "uuid",
          "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
        },
      },
      "status": {
        "type": "string",
        "enum": ["draft", "published", "archived"],
      },
      "expectedVersion": {
        "type": "integer",
        "minimum": 0,
        "maximum": 9007199254740991,
      },
    },
    "required": ["title", "body", "type", "status"],
    "additionalProperties": false,
  },
  "TrainingGetResponse": {"\$ref": "#/components/schemas/TrainingContent"},
  "TrainingStartResponse": {"\$ref": "#/components/schemas/UploadStarted"},
  "TrainingStartRequest": {
    "type": "object",
    "properties": {
      "purpose": {
        "type": "string",
        "enum": ["training", "catalog", "store", "reward", "group"],
      },
      "organizationId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "storeId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "sha256": {"type": "string", "pattern": "^[a-f0-9]{64}\$"},
      "fileName": {"type": "string", "minLength": 1, "maxLength": 200},
      "mime": {
        "type": "string",
        "enum": ["image/jpeg", "image/png", "video/mp4", "video/quicktime"],
      },
      "size": {"type": "integer", "exclusiveMinimum": 0, "maximum": 524288000},
    },
    "required": ["fileName", "mime", "size"],
    "additionalProperties": false,
  },
  "TrainingStatusResponse": {"\$ref": "#/components/schemas/UploadStatus"},
  "TrainingChunkResponse": {"\$ref": "#/components/schemas/UploadChunkResult"},
  "TrainingMetadataResponse": {"\$ref": "#/components/schemas/MediaMetadata"},
  "TrainingMediaResponse": {"type": "string", "format": "binary"},
  "ReportingOverviewResponse": {"\$ref": "#/components/schemas/ReportOverview"},
  "ReportingExportResponse": {"type": "string"},
  "ApiErrorFieldsItem": {
    "type": "object",
    "properties": {
      "path": {"type": "string"},
      "message": {"type": "string"},
    },
    "required": ["path", "message"],
    "additionalProperties": false,
  },
  "SyncResultAccepted": {
    "type": "object",
    "properties": {
      "operationId": {"type": "string", "format": "uuid"},
      "status": {"const": "accepted", "type": "string"},
      "data": {"\$ref": "#/components/schemas/CommandOutcome"},
      "committedCursor": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "affectedVersions": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/AffectedVersion"},
      },
    },
    "required": ["operationId", "status", "data"],
    "additionalProperties": false,
  },
  "SyncResultConflict": {
    "type": "object",
    "properties": {
      "operationId": {"type": "string", "format": "uuid"},
      "status": {"const": "conflict", "type": "string"},
      "code": {"type": "string"},
      "message": {"type": "string"},
      "retryAfterMs": {"type": "integer"},
    },
    "required": ["operationId", "status", "code", "message"],
    "additionalProperties": false,
  },
  "SyncResultRejected": {
    "type": "object",
    "properties": {
      "operationId": {"type": "string", "format": "uuid"},
      "status": {"const": "rejected", "type": "string"},
      "code": {"type": "string"},
      "message": {"type": "string"},
      "retryAfterMs": {"type": "integer"},
    },
    "required": ["operationId", "status", "code", "message"],
    "additionalProperties": false,
  },
  "SyncResultBlocked": {
    "type": "object",
    "properties": {
      "operationId": {"type": "string", "format": "uuid"},
      "status": {"const": "blocked", "type": "string"},
      "code": {"type": "string"},
      "message": {"type": "string"},
      "retryAfterMs": {"type": "integer"},
    },
    "required": ["operationId", "status", "code", "message"],
    "additionalProperties": false,
  },
  "SyncResultRetryable": {
    "type": "object",
    "properties": {
      "operationId": {"type": "string", "format": "uuid"},
      "status": {"const": "retryable", "type": "string"},
      "code": {"type": "string"},
      "message": {"type": "string"},
      "retryAfterMs": {"type": "integer"},
    },
    "required": ["operationId", "status", "code", "message"],
    "additionalProperties": false,
  },
  "OperationStatusUnknown": {
    "type": "object",
    "properties": {
      "operationId": {"type": "string", "format": "uuid"},
      "status": {"const": "unknown", "type": "string"},
    },
    "required": ["operationId", "status"],
    "additionalProperties": false,
  },
  "SnapshotPageLots": {
    "type": "object",
    "properties": {
      "resource": {"const": "lots", "type": "string"},
      "items": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/InventoryLot"},
      },
      "nextPage": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "cursor": {"type": "string", "pattern": "^-?[0-9]+\$"},
    },
    "required": ["resource", "items", "nextPage", "cursor"],
    "additionalProperties": false,
  },
  "SnapshotPageProducts": {
    "type": "object",
    "properties": {
      "resource": {"const": "products", "type": "string"},
      "items": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/Product"},
      },
      "nextPage": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "cursor": {"type": "string", "pattern": "^-?[0-9]+\$"},
    },
    "required": ["resource", "items", "nextPage", "cursor"],
    "additionalProperties": false,
  },
  "SnapshotPageConfig": {
    "type": "object",
    "properties": {
      "resource": {"const": "config", "type": "string"},
      "items": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/StoreProduct"},
      },
      "nextPage": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "cursor": {"type": "string", "pattern": "^-?[0-9]+\$"},
    },
    "required": ["resource", "items", "nextPage", "cursor"],
    "additionalProperties": false,
  },
  "SnapshotPageRewards": {
    "type": "object",
    "properties": {
      "resource": {"const": "rewards", "type": "string"},
      "items": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/Reward"},
      },
      "nextPage": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "cursor": {"type": "string", "pattern": "^-?[0-9]+\$"},
    },
    "required": ["resource", "items", "nextPage", "cursor"],
    "additionalProperties": false,
  },
  "SnapshotPageClaims": {
    "type": "object",
    "properties": {
      "resource": {"const": "claims", "type": "string"},
      "items": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/RewardClaim"},
      },
      "nextPage": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "cursor": {"type": "string", "pattern": "^-?[0-9]+\$"},
    },
    "required": ["resource", "items", "nextPage", "cursor"],
    "additionalProperties": false,
  },
  "SnapshotPageOrders": {
    "type": "object",
    "properties": {
      "resource": {"const": "orders", "type": "string"},
      "items": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/Order"},
      },
      "nextPage": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "cursor": {"type": "string", "pattern": "^-?[0-9]+\$"},
    },
    "required": ["resource", "items", "nextPage", "cursor"],
    "additionalProperties": false,
  },
  "SnapshotPageDeliveries": {
    "type": "object",
    "properties": {
      "resource": {"const": "deliveries", "type": "string"},
      "items": {
        "type": "array",
        "items": {"\$ref": "#/components/schemas/Delivery"},
      },
      "nextPage": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "cursor": {"type": "string", "pattern": "^-?[0-9]+\$"},
    },
    "required": ["resource", "items", "nextPage", "cursor"],
    "additionalProperties": false,
  },
  "SnapshotSnapshotPages": {
    "type": "object",
    "properties": {
      "lots": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "config": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "products": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "rewards": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "claims": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "orders": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "deliveries": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
    },
    "required": [],
    "additionalProperties": false,
  },
  "SnapshotSummary": {
    "type": "object",
    "properties": {
      "saleCount": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "totalMillimes": {"type": "string", "pattern": "^-?[0-9]+\$"},
    },
    "required": ["saleCount", "totalMillimes"],
    "additionalProperties": false,
  },
  "SnapshotPagination": {
    "type": "object",
    "properties": {
      "lots": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "products": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "config": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
    },
    "required": ["lots", "products", "config"],
    "additionalProperties": false,
  },
  "AttentionPageItemsItem": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "productId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "kind": {
        "type": "string",
        "enum": ["low_stock", "expired", "deliveries", "rewards"],
      },
      "title": {"type": "string"},
      "detail": {"type": "string"},
      "storeName": {"type": "string"},
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "productId",
      "kind",
      "title",
      "detail",
      "storeName",
    ],
    "additionalProperties": false,
  },
  "GroupPageCreationGrantsItem": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
    },
    "required": ["id"],
    "additionalProperties": false,
  },
  "GroupTeamMembersItem": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "name": {"type": "string"},
      "email": {"type": "string"},
      "role": {
        "type": "string",
        "enum": ["responsible", "salesperson"],
      },
      "active": {"type": "boolean"},
      "storeIds": {
        "type": "array",
        "items": {"type": "string", "format": "uuid"},
      },
    },
    "required": ["id", "name", "email", "role", "active", "storeIds"],
    "additionalProperties": false,
  },
  "GroupTeamInvitationsItem": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "email": {"type": "string"},
      "kind": {"type": "string"},
      "storeIds": {
        "type": "array",
        "items": {"type": "string", "format": "uuid"},
      },
      "storeId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "expiresAt": {"type": "string", "format": "date-time"},
    },
    "required": ["id", "email", "kind", "storeIds", "storeId", "expiresAt"],
    "additionalProperties": false,
  },
  "DashboardSeriesItem": {
    "type": "object",
    "properties": {
      "day": {"type": "string"},
      "netMillimes": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "netUnits": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "saleCount": {"type": "string", "pattern": "^-?[0-9]+\$"},
    },
    "required": ["day", "netMillimes", "netUnits", "saleCount"],
    "additionalProperties": false,
  },
  "DashboardComparisonsItem": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "name": {"type": "string"},
      "netMillimes": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "netUnits": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "saleCount": {"type": "string", "pattern": "^-?[0-9]+\$"},
    },
    "required": ["id", "name", "netMillimes", "netUnits", "saleCount"],
    "additionalProperties": false,
  },
  "DashboardProductsItem": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "name": {"type": "string"},
      "imageId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "netUnits": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "netMillimes": {"type": "string", "pattern": "^-?[0-9]+\$"},
    },
    "required": ["id", "name", "imageId", "netUnits", "netMillimes"],
    "additionalProperties": false,
  },
  "DashboardRecentSalesItem": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "occurredAt": {"type": "string", "format": "date-time"},
      "netMillimes": {"type": "string", "pattern": "^-?[0-9]+\$"},
      "netUnits": {"type": "string", "pattern": "^-?[0-9]+\$"},
    },
    "required": ["id", "occurredAt", "netMillimes", "netUnits"],
    "additionalProperties": false,
  },
  "DashboardRanking": {
    "type": "object",
    "properties": {
      "month": {"type": "string"},
      "rank": {
        "anyOf": [
          {"type": "string", "pattern": "^-?[0-9]+\$"},
          {"type": "null"},
        ],
      },
      "score": {"type": "string", "pattern": "^-?[0-9]+\$"},
    },
    "required": ["month", "rank", "score"],
    "additionalProperties": false,
  },
  "DashboardCurrent": {
    "type": "object",
    "properties": {
      "pendingOrders": {"type": "integer"},
      "pendingDeliveries": {"type": "integer"},
      "pendingClaims": {"type": "integer"},
      "expiredLots": {"type": "integer"},
      "expiringLots": {"type": "integer"},
      "lowStock": {"type": "integer"},
      "availablePoints": {
        "anyOf": [
          {"type": "string", "pattern": "^-?[0-9]+\$"},
          {"type": "null"},
        ],
      },
      "reservedPoints": {
        "anyOf": [
          {"type": "string", "pattern": "^-?[0-9]+\$"},
          {"type": "null"},
        ],
      },
    },
    "required": [
      "pendingOrders",
      "pendingDeliveries",
      "pendingClaims",
      "expiredLots",
      "expiringLots",
      "lowStock",
      "availablePoints",
      "reservedPoints",
    ],
    "additionalProperties": false,
  },
  "DashboardAlertsItem": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "organizationId": {"type": "string", "format": "uuid"},
      "storeId": {"type": "string", "format": "uuid"},
      "productId": {
        "anyOf": [
          {"type": "string", "format": "uuid"},
          {"type": "null"},
        ],
      },
      "kind": {"type": "string"},
      "message": {"type": "string"},
      "storeName": {"type": "string"},
    },
    "required": [
      "id",
      "organizationId",
      "storeId",
      "productId",
      "kind",
      "message",
      "storeName",
    ],
    "additionalProperties": false,
  },
  "DeliveryIssueHeldLinesItem": {
    "type": "object",
    "properties": {
      "productId": {"type": "string", "format": "uuid"},
      "quantity": {"type": "integer"},
    },
    "required": ["productId", "quantity"],
    "additionalProperties": false,
  },
  "ScopedOrderRequestedLinesItem": {
    "type": "object",
    "properties": {
      "productId": {"type": "string", "format": "uuid"},
      "quantity": {"type": "integer"},
    },
    "required": ["productId", "quantity"],
    "additionalProperties": false,
  },
  "ScopedOrderCancelledLinesItem": {
    "type": "object",
    "properties": {
      "productId": {"type": "string", "format": "uuid"},
      "quantity": {"type": "integer"},
    },
    "required": ["productId", "quantity"],
    "additionalProperties": false,
  },
  "ScopedOrderLinesItem": {
    "type": "object",
    "properties": {
      "productId": {"type": "string", "format": "uuid"},
      "quantity": {"type": "integer"},
    },
    "required": ["productId", "quantity"],
    "additionalProperties": false,
  },
  "ScopedOrderDetailsHistoryItem": {
    "type": "object",
    "properties": {
      "id": {"type": "string", "format": "uuid"},
      "action": {"type": "string"},
      "actorId": {"type": "string", "format": "uuid"},
      "createdAt": {"type": "string", "format": "date-time"},
      "details": {"\$ref": "#/components/schemas/JsonValue"},
    },
    "required": ["id", "action", "actorId", "createdAt", "details"],
    "additionalProperties": false,
  },
  "CommandSaleCreate": {
    "type": "object",
    "properties": {
      "type": {"type": "string", "const": "sale.create"},
      "batchDeclarations": {
        "maxItems": 5000,
        "type": "array",
        "items": {
          "\$ref":
              "#/components/schemas/CommandSaleCreateBatchDeclarationsItem",
        },
      },
      "saleId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "occurredAt": {
        "type": "string",
        "format": "date-time",
        "pattern": "^(?:(?:\\d\\d[2468][048]|\\d\\d[13579][26]|\\d\\d0[48]|[02468][048]00|[13579][26]00)-02-29|\\d{4}-(?:(?:0[13578]|1[02])-(?:0[1-9]|[12]\\d|3[01])|(?:0[469]|11)-(?:0[1-9]|[12]\\d|30)|(?:02)-(?:0[1-9]|1\\d|2[0-8])))T(?:(?:[01]\\d|2[0-3]):[0-5]\\d:[0-5]\\d(?:\\.\\d+)?(?:Z|([+-](?:[01]\\d|2[0-3]):[0-5]\\d)))\$",
      },
      "lines": {
        "minItems": 1,
        "maxItems": 100,
        "type": "array",
        "items": {"\$ref": "#/components/schemas/CommandSaleCreateLinesItem"},
      },
    },
    "required": ["type", "saleId", "occurredAt", "lines"],
    "additionalProperties": false,
  },
  "CommandSaleCorrect": {
    "type": "object",
    "properties": {
      "type": {"type": "string", "const": "sale.correct"},
      "batchDeclarations": {
        "maxItems": 5000,
        "type": "array",
        "items": {
          "\$ref":
              "#/components/schemas/CommandSaleCorrectBatchDeclarationsItem",
        },
      },
      "saleId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "occurredAt": {
        "type": "string",
        "format": "date-time",
        "pattern": "^(?:(?:\\d\\d[2468][048]|\\d\\d[13579][26]|\\d\\d0[48]|[02468][048]00|[13579][26]00)-02-29|\\d{4}-(?:(?:0[13578]|1[02])-(?:0[1-9]|[12]\\d|3[01])|(?:0[469]|11)-(?:0[1-9]|[12]\\d|30)|(?:02)-(?:0[1-9]|1\\d|2[0-8])))T(?:(?:[01]\\d|2[0-3]):[0-5]\\d:[0-5]\\d(?:\\.\\d+)?(?:Z|([+-](?:[01]\\d|2[0-3]):[0-5]\\d)))\$",
      },
      "lines": {
        "minItems": 1,
        "maxItems": 100,
        "type": "array",
        "items": {"\$ref": "#/components/schemas/CommandSaleCorrectLinesItem"},
      },
      "reason": {"type": "string", "minLength": 3, "maxLength": 300},
    },
    "required": ["type", "saleId", "occurredAt", "lines", "reason"],
    "additionalProperties": false,
  },
  "CommandSaleReturn": {
    "type": "object",
    "properties": {
      "type": {"type": "string", "const": "sale.return"},
      "saleId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "reason": {"type": "string", "minLength": 3, "maxLength": 300},
      "lines": {
        "minItems": 1,
        "maxItems": 100,
        "type": "array",
        "items": {"\$ref": "#/components/schemas/CommandSaleReturnLinesItem"},
      },
    },
    "required": ["type", "saleId", "reason", "lines"],
    "additionalProperties": false,
  },
  "CommandStockReceive": {
    "type": "object",
    "properties": {
      "type": {"type": "string", "const": "stock.receive"},
      "lines": {
        "minItems": 1,
        "maxItems": 200,
        "type": "array",
        "items": {"\$ref": "#/components/schemas/CommandStockReceiveLinesItem"},
      },
      "reason": {
        "type": "string",
        "enum": ["opening", "receipt"],
      },
    },
    "required": ["type", "lines", "reason"],
    "additionalProperties": false,
  },
  "CommandStockAdjust": {
    "type": "object",
    "properties": {
      "type": {"type": "string", "const": "stock.adjust"},
      "lotId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "quantity": {"type": "integer", "minimum": 0, "maximum": 1000000},
      "reason": {"type": "string", "minLength": 3, "maxLength": 300},
    },
    "required": ["type", "lotId", "quantity", "reason"],
    "additionalProperties": false,
  },
  "CommandStockDamage": {
    "type": "object",
    "properties": {
      "type": {"type": "string", "const": "stock.damage"},
      "lotId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "quantity": {"type": "integer", "minimum": 1, "maximum": 1000000},
      "reason": {"type": "string", "minLength": 3, "maxLength": 300},
    },
    "required": ["type", "lotId", "quantity", "reason"],
    "additionalProperties": false,
  },
  "CommandOrderCreate": {
    "type": "object",
    "properties": {
      "type": {"type": "string", "const": "order.create"},
      "orderId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "lines": {
        "minItems": 1,
        "maxItems": 200,
        "type": "array",
        "items": {"\$ref": "#/components/schemas/CommandOrderCreateLinesItem"},
      },
    },
    "required": ["type", "orderId", "lines"],
    "additionalProperties": false,
  },
  "CommandOrderPrepare": {
    "type": "object",
    "properties": {
      "type": {"type": "string", "const": "order.prepare"},
      "orderId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
    },
    "required": ["type", "orderId"],
    "additionalProperties": false,
  },
  "CommandOrderAmend": {
    "type": "object",
    "properties": {
      "type": {"type": "string", "const": "order.amend"},
      "orderId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "lines": {
        "minItems": 1,
        "maxItems": 200,
        "type": "array",
        "items": {"\$ref": "#/components/schemas/CommandOrderAmendLinesItem"},
      },
      "reason": {"type": "string", "minLength": 3, "maxLength": 500},
    },
    "required": ["type", "orderId", "lines", "reason"],
    "additionalProperties": false,
  },
  "CommandOrderCancel": {
    "type": "object",
    "properties": {
      "type": {"type": "string", "const": "order.cancel"},
      "orderId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "reason": {"type": "string", "minLength": 3, "maxLength": 500},
    },
    "required": ["type", "orderId", "reason"],
    "additionalProperties": false,
  },
  "CommandDeliveryReport": {
    "type": "object",
    "properties": {
      "type": {"type": "string", "const": "delivery.report"},
      "deliveryId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "reason": {"type": "string", "minLength": 3, "maxLength": 500},
    },
    "required": ["type", "deliveryId", "reason"],
    "additionalProperties": false,
  },
  "CommandDeliveryResolve": {
    "type": "object",
    "properties": {
      "type": {"type": "string", "const": "delivery.resolve"},
      "deliveryId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "decision": {
        "type": "string",
        "enum": ["tracing", "lost", "returned", "settled"],
      },
      "reason": {"type": "string", "minLength": 3, "maxLength": 500},
    },
    "required": ["type", "deliveryId", "decision", "reason"],
    "additionalProperties": false,
  },
  "CommandDeliveryDispatch": {
    "type": "object",
    "properties": {
      "type": {"type": "string", "const": "delivery.dispatch"},
      "orderId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "deliveryId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "lines": {
        "minItems": 1,
        "maxItems": 200,
        "type": "array",
        "items": {
          "\$ref": "#/components/schemas/CommandDeliveryDispatchLinesItem",
        },
      },
    },
    "required": ["type", "orderId", "deliveryId", "lines"],
    "additionalProperties": false,
  },
  "CommandDeliveryReceive": {
    "type": "object",
    "properties": {
      "type": {"type": "string", "const": "delivery.receive"},
      "deliveryId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "lines": {
        "maxItems": 200,
        "type": "array",
        "items": {
          "\$ref": "#/components/schemas/CommandDeliveryReceiveLinesItem",
        },
      },
      "note": {"default": "", "type": "string", "maxLength": 500},
    },
    "required": ["type", "deliveryId", "lines"],
    "additionalProperties": false,
  },
  "CommandRewardRequest": {
    "type": "object",
    "properties": {
      "type": {"type": "string", "const": "reward.request"},
      "claimId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "rewardId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
    },
    "required": ["type", "claimId", "rewardId"],
    "additionalProperties": false,
  },
  "CommandRewardResolve": {
    "type": "object",
    "properties": {
      "type": {"type": "string", "const": "reward.resolve"},
      "claimId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "decision": {
        "type": "string",
        "enum": ["fulfilled", "cancelled", "rejected"],
      },
    },
    "required": ["type", "claimId", "decision"],
    "additionalProperties": false,
  },
  "CatalogImportResultTrue": {
    "type": "object",
    "properties": {
      "valid": {"const": true, "type": "boolean"},
      "count": {"type": "integer"},
      "rows": {
        "type": "array",
        "items": {
          "\$ref": "#/components/schemas/CatalogImportResultTrueRowsItem",
        },
      },
    },
    "required": ["valid", "count", "rows"],
    "additionalProperties": false,
  },
  "ExportCreateRequestQuery": {
    "anyOf": [
      {"\$ref": "#/components/schemas/ExportCreateRequestQueryHistory"},
      {"\$ref": "#/components/schemas/ExportCreateRequestQuery2"},
    ],
  },
  "CatalogImportRequestRowsItem": {
    "type": "object",
    "properties": {
      "reference": {"type": "string", "minLength": 1, "maxLength": 80},
      "name": {"type": "string", "minLength": 2, "maxLength": 160},
      "barcode": {"type": "string", "minLength": 3, "maxLength": 80},
      "description": {"default": "", "type": "string", "maxLength": 5000},
      "category": {"type": "string", "maxLength": 100},
      "range": {"type": "string", "maxLength": 100},
      "packageSize": {"type": "string", "maxLength": 80},
      "instructions": {"type": "string", "maxLength": 5000},
      "ingredients": {"type": "string", "maxLength": 5000},
      "precautions": {"type": "string", "maxLength": 5000},
      "referencePriceMillimes": {
        "anyOf": [
          {"type": "string", "pattern": "^(0|[1-9]\\d{0,14})\$"},
          {"type": "null"},
        ],
      },
      "priceStatus": {
        "type": "string",
        "enum": ["missing", "verified", "sample"],
      },
      "sourceUrls": {
        "maxItems": 12,
        "type": "array",
        "items": {"type": "string", "maxLength": 2000, "format": "uri"},
      },
      "active": {"default": true, "type": "boolean"},
    },
    "required": ["reference", "name"],
    "additionalProperties": false,
  },
  "CommandSaleCreateBatchDeclarationsItem": {
    "type": "object",
    "properties": {
      "lotId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "productId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "batch": {"type": "string", "minLength": 1, "maxLength": 100},
      "expiry": {"type": "string", "maxLength": 10},
    },
    "required": ["lotId", "productId", "batch", "expiry"],
    "additionalProperties": false,
  },
  "CommandSaleCreateLinesItem": {
    "type": "object",
    "properties": {
      "id": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "productId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "quantity": {"type": "integer", "minimum": 1, "maximum": 1000000},
      "unitPriceMillimes": {
        "type": "string",
        "pattern": "^(0|[1-9]\\d{0,14})\$",
      },
      "allocations": {
        "minItems": 1,
        "maxItems": 50,
        "type": "array",
        "items": {
          "\$ref":
              "#/components/schemas/CommandSaleCreateLinesItemAllocationsItem",
        },
      },
    },
    "required": [
      "id",
      "productId",
      "quantity",
      "unitPriceMillimes",
      "allocations",
    ],
    "additionalProperties": false,
  },
  "CommandSaleCorrectBatchDeclarationsItem": {
    "type": "object",
    "properties": {
      "lotId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "productId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "batch": {"type": "string", "minLength": 1, "maxLength": 100},
      "expiry": {"type": "string", "maxLength": 10},
    },
    "required": ["lotId", "productId", "batch", "expiry"],
    "additionalProperties": false,
  },
  "CommandSaleCorrectLinesItem": {
    "type": "object",
    "properties": {
      "id": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "productId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "quantity": {"type": "integer", "minimum": 1, "maximum": 1000000},
      "unitPriceMillimes": {
        "type": "string",
        "pattern": "^(0|[1-9]\\d{0,14})\$",
      },
      "allocations": {
        "minItems": 1,
        "maxItems": 50,
        "type": "array",
        "items": {
          "\$ref":
              "#/components/schemas/CommandSaleCorrectLinesItemAllocationsItem",
        },
      },
    },
    "required": [
      "id",
      "productId",
      "quantity",
      "unitPriceMillimes",
      "allocations",
    ],
    "additionalProperties": false,
  },
  "CommandSaleReturnLinesItem": {
    "type": "object",
    "properties": {
      "lineId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "lotId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "quantity": {"type": "integer", "minimum": 1, "maximum": 1000000},
      "sellable": {"type": "boolean"},
    },
    "required": ["lineId", "lotId", "quantity", "sellable"],
    "additionalProperties": false,
  },
  "CommandStockReceiveLinesItem": {
    "type": "object",
    "properties": {
      "productId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "batch": {"type": "string", "minLength": 1, "maxLength": 100},
      "expiry": {"type": "string", "maxLength": 10},
      "quantity": {"type": "integer", "minimum": 1, "maximum": 1000000},
    },
    "required": ["productId", "batch", "expiry", "quantity"],
    "additionalProperties": false,
  },
  "CommandOrderCreateLinesItem": {
    "type": "object",
    "properties": {
      "productId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "quantity": {"type": "integer", "minimum": 1, "maximum": 1000000},
    },
    "required": ["productId", "quantity"],
    "additionalProperties": false,
  },
  "CommandOrderAmendLinesItem": {
    "type": "object",
    "properties": {
      "productId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "quantity": {"type": "integer", "minimum": 1, "maximum": 1000000},
    },
    "required": ["productId", "quantity"],
    "additionalProperties": false,
  },
  "CommandDeliveryDispatchLinesItem": {
    "type": "object",
    "properties": {
      "productId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "quantity": {"type": "integer", "minimum": 1, "maximum": 1000000},
    },
    "required": ["productId", "quantity"],
    "additionalProperties": false,
  },
  "CommandDeliveryReceiveLinesItem": {
    "type": "object",
    "properties": {
      "productId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "batch": {"type": "string", "minLength": 1, "maxLength": 100},
      "expiry": {"type": "string", "maxLength": 10},
      "quantity": {"type": "integer", "minimum": 1, "maximum": 1000000},
      "condition": {
        "type": "string",
        "enum": ["sellable", "damaged", "refused"],
      },
    },
    "required": ["productId", "batch", "expiry", "quantity"],
    "additionalProperties": false,
  },
  "CatalogImportResultTrueRowsItem": {
    "\$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
      "reference": {"type": "string", "minLength": 1, "maxLength": 80},
      "name": {"type": "string", "minLength": 2, "maxLength": 160},
      "barcode": {"type": "string", "minLength": 3, "maxLength": 80},
      "description": {"default": "", "type": "string", "maxLength": 5000},
      "category": {"type": "string", "maxLength": 100},
      "range": {"type": "string", "maxLength": 100},
      "packageSize": {"type": "string", "maxLength": 80},
      "instructions": {"type": "string", "maxLength": 5000},
      "ingredients": {"type": "string", "maxLength": 5000},
      "precautions": {"type": "string", "maxLength": 5000},
      "referencePriceMillimes": {
        "anyOf": [
          {"type": "string", "pattern": "^(0|[1-9]\\d{0,14})\$"},
          {"type": "null"},
        ],
      },
      "priceStatus": {
        "type": "string",
        "enum": ["missing", "verified", "sample"],
      },
      "sourceUrls": {
        "maxItems": 12,
        "type": "array",
        "items": {"type": "string", "maxLength": 2000, "format": "uri"},
      },
      "active": {"default": true, "type": "boolean"},
    },
    "required": ["reference", "name"],
    "additionalProperties": false,
  },
  "ExportCreateRequestQueryHistory": {
    "type": "object",
    "properties": {
      "kind": {"type": "string", "const": "history"},
      "organizationId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "storeId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "resource": {
        "type": "string",
        "enum": ["movements", "points", "audit"],
      },
      "productId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
    },
    "required": ["kind", "organizationId", "storeId", "resource"],
    "additionalProperties": false,
  },
  "ExportCreateRequestQuery2": {
    "type": "object",
    "properties": {
      "scope": {
        "type": "string",
        "enum": ["network", "group", "store", "personal"],
      },
      "organizationId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "storeId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "from": {
        "type": "string",
        "format": "date",
        "pattern": "^(?:(?:\\d\\d[2468][048]|\\d\\d[13579][26]|\\d\\d0[48]|[02468][048]00|[13579][26]00)-02-29|\\d{4}-(?:(?:0[13578]|1[02])-(?:0[1-9]|[12]\\d|3[01])|(?:0[469]|11)-(?:0[1-9]|[12]\\d|30)|(?:02)-(?:0[1-9]|1\\d|2[0-8])))\$",
      },
      "to": {
        "type": "string",
        "format": "date",
        "pattern": "^(?:(?:\\d\\d[2468][048]|\\d\\d[13579][26]|\\d\\d0[48]|[02468][048]00|[13579][26]00)-02-29|\\d{4}-(?:(?:0[13578]|1[02])-(?:0[1-9]|[12]\\d|3[01])|(?:0[469]|11)-(?:0[1-9]|[12]\\d|30)|(?:02)-(?:0[1-9]|1\\d|2[0-8])))\$",
      },
    },
    "required": ["scope", "from", "to"],
  },
  "CommandSaleCreateLinesItemAllocationsItem": {
    "type": "object",
    "properties": {
      "lotId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "quantity": {"type": "integer", "minimum": 1, "maximum": 1000000},
    },
    "required": ["lotId", "quantity"],
    "additionalProperties": false,
  },
  "CommandSaleCorrectLinesItemAllocationsItem": {
    "type": "object",
    "properties": {
      "lotId": {
        "type": "string",
        "format": "uuid",
        "pattern": "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\$",
      },
      "quantity": {"type": "integer", "minimum": 1, "maximum": 1000000},
    },
    "required": ["lotId", "quantity"],
    "additionalProperties": false,
  },
};

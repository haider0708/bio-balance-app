// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $CacheEntriesTable extends CacheEntries
    with TableInfo<$CacheEntriesTable, CacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _storeIdMeta = const VerificationMeta(
    'storeId',
  );
  @override
  late final GeneratedColumn<String> storeId = GeneratedColumn<String>(
    'store_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resourceMeta = const VerificationMeta(
    'resource',
  );
  @override
  late final GeneratedColumn<String> resource = GeneratedColumn<String>(
    'resource',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    storeId,
    resource,
    entityId,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cache_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<CacheEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('store_id')) {
      context.handle(
        _storeIdMeta,
        storeId.isAcceptableOrUnknown(data['store_id']!, _storeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_storeIdMeta);
    }
    if (data.containsKey('resource')) {
      context.handle(
        _resourceMeta,
        resource.isAcceptableOrUnknown(data['resource']!, _resourceMeta),
      );
    } else if (isInserting) {
      context.missing(_resourceMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    accountId,
    storeId,
    resource,
    entityId,
  };
  @override
  CacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CacheEntry(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      storeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_id'],
      )!,
      resource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resource'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $CacheEntriesTable createAlias(String alias) {
    return $CacheEntriesTable(attachedDatabase, alias);
  }
}

class CacheEntry extends DataClass implements Insertable<CacheEntry> {
  final String accountId;
  final String storeId;
  final String resource;
  final String entityId;
  final String payload;
  const CacheEntry({
    required this.accountId,
    required this.storeId,
    required this.resource,
    required this.entityId,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['store_id'] = Variable<String>(storeId);
    map['resource'] = Variable<String>(resource);
    map['entity_id'] = Variable<String>(entityId);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  CacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return CacheEntriesCompanion(
      accountId: Value(accountId),
      storeId: Value(storeId),
      resource: Value(resource),
      entityId: Value(entityId),
      payload: Value(payload),
    );
  }

  factory CacheEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CacheEntry(
      accountId: serializer.fromJson<String>(json['accountId']),
      storeId: serializer.fromJson<String>(json['storeId']),
      resource: serializer.fromJson<String>(json['resource']),
      entityId: serializer.fromJson<String>(json['entityId']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'storeId': serializer.toJson<String>(storeId),
      'resource': serializer.toJson<String>(resource),
      'entityId': serializer.toJson<String>(entityId),
      'payload': serializer.toJson<String>(payload),
    };
  }

  CacheEntry copyWith({
    String? accountId,
    String? storeId,
    String? resource,
    String? entityId,
    String? payload,
  }) => CacheEntry(
    accountId: accountId ?? this.accountId,
    storeId: storeId ?? this.storeId,
    resource: resource ?? this.resource,
    entityId: entityId ?? this.entityId,
    payload: payload ?? this.payload,
  );
  CacheEntry copyWithCompanion(CacheEntriesCompanion data) {
    return CacheEntry(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      storeId: data.storeId.present ? data.storeId.value : this.storeId,
      resource: data.resource.present ? data.resource.value : this.resource,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntry(')
          ..write('accountId: $accountId, ')
          ..write('storeId: $storeId, ')
          ..write('resource: $resource, ')
          ..write('entityId: $entityId, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(accountId, storeId, resource, entityId, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CacheEntry &&
          other.accountId == this.accountId &&
          other.storeId == this.storeId &&
          other.resource == this.resource &&
          other.entityId == this.entityId &&
          other.payload == this.payload);
}

class CacheEntriesCompanion extends UpdateCompanion<CacheEntry> {
  final Value<String> accountId;
  final Value<String> storeId;
  final Value<String> resource;
  final Value<String> entityId;
  final Value<String> payload;
  final Value<int> rowid;
  const CacheEntriesCompanion({
    this.accountId = const Value.absent(),
    this.storeId = const Value.absent(),
    this.resource = const Value.absent(),
    this.entityId = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CacheEntriesCompanion.insert({
    required String accountId,
    required String storeId,
    required String resource,
    required String entityId,
    required String payload,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       storeId = Value(storeId),
       resource = Value(resource),
       entityId = Value(entityId),
       payload = Value(payload);
  static Insertable<CacheEntry> custom({
    Expression<String>? accountId,
    Expression<String>? storeId,
    Expression<String>? resource,
    Expression<String>? entityId,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (storeId != null) 'store_id': storeId,
      if (resource != null) 'resource': resource,
      if (entityId != null) 'entity_id': entityId,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CacheEntriesCompanion copyWith({
    Value<String>? accountId,
    Value<String>? storeId,
    Value<String>? resource,
    Value<String>? entityId,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return CacheEntriesCompanion(
      accountId: accountId ?? this.accountId,
      storeId: storeId ?? this.storeId,
      resource: resource ?? this.resource,
      entityId: entityId ?? this.entityId,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (storeId.present) {
      map['store_id'] = Variable<String>(storeId.value);
    }
    if (resource.present) {
      map['resource'] = Variable<String>(resource.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntriesCompanion(')
          ..write('accountId: $accountId, ')
          ..write('storeId: $storeId, ')
          ..write('resource: $resource, ')
          ..write('entityId: $entityId, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxRowsTable extends OutboxRows
    with TableInfo<$OutboxRowsTable, OutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _storeIdMeta = const VerificationMeta(
    'storeId',
  );
  @override
  late final GeneratedColumn<String> storeId = GeneratedColumn<String>(
    'store_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _effectMeta = const VerificationMeta('effect');
  @override
  late final GeneratedColumn<String> effect = GeneratedColumn<String>(
    'effect',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resolutionMeta = const VerificationMeta(
    'resolution',
  );
  @override
  late final GeneratedColumn<String> resolution = GeneratedColumn<String>(
    'resolution',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resolvedAtMeta = const VerificationMeta(
    'resolvedAt',
  );
  @override
  late final GeneratedColumn<DateTime> resolvedAt = GeneratedColumn<DateTime>(
    'resolved_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sequence,
    operationId,
    accountId,
    storeId,
    payload,
    effect,
    status,
    error,
    resolution,
    resolvedAt,
    attempts,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    }
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('store_id')) {
      context.handle(
        _storeIdMeta,
        storeId.isAcceptableOrUnknown(data['store_id']!, _storeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_storeIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('effect')) {
      context.handle(
        _effectMeta,
        effect.isAcceptableOrUnknown(data['effect']!, _effectMeta),
      );
    } else if (isInserting) {
      context.missing(_effectMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('resolution')) {
      context.handle(
        _resolutionMeta,
        resolution.isAcceptableOrUnknown(data['resolution']!, _resolutionMeta),
      );
    }
    if (data.containsKey('resolved_at')) {
      context.handle(
        _resolvedAtMeta,
        resolvedAt.isAcceptableOrUnknown(data['resolved_at']!, _resolvedAtMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sequence};
  @override
  OutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxRow(
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      storeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      effect: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}effect'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      resolution: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resolution'],
      ),
      resolvedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}resolved_at'],
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $OutboxRowsTable createAlias(String alias) {
    return $OutboxRowsTable(attachedDatabase, alias);
  }
}

class OutboxRow extends DataClass implements Insertable<OutboxRow> {
  final int sequence;
  final String operationId;
  final String accountId;
  final String storeId;
  final String payload;
  final String effect;
  final String status;
  final String? error;
  final String? resolution;
  final DateTime? resolvedAt;
  final int attempts;
  final DateTime createdAt;
  const OutboxRow({
    required this.sequence,
    required this.operationId,
    required this.accountId,
    required this.storeId,
    required this.payload,
    required this.effect,
    required this.status,
    this.error,
    this.resolution,
    this.resolvedAt,
    required this.attempts,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sequence'] = Variable<int>(sequence);
    map['operation_id'] = Variable<String>(operationId);
    map['account_id'] = Variable<String>(accountId);
    map['store_id'] = Variable<String>(storeId);
    map['payload'] = Variable<String>(payload);
    map['effect'] = Variable<String>(effect);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    if (!nullToAbsent || resolution != null) {
      map['resolution'] = Variable<String>(resolution);
    }
    if (!nullToAbsent || resolvedAt != null) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt);
    }
    map['attempts'] = Variable<int>(attempts);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  OutboxRowsCompanion toCompanion(bool nullToAbsent) {
    return OutboxRowsCompanion(
      sequence: Value(sequence),
      operationId: Value(operationId),
      accountId: Value(accountId),
      storeId: Value(storeId),
      payload: Value(payload),
      effect: Value(effect),
      status: Value(status),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      resolution: resolution == null && nullToAbsent
          ? const Value.absent()
          : Value(resolution),
      resolvedAt: resolvedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAt),
      attempts: Value(attempts),
      createdAt: Value(createdAt),
    );
  }

  factory OutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxRow(
      sequence: serializer.fromJson<int>(json['sequence']),
      operationId: serializer.fromJson<String>(json['operationId']),
      accountId: serializer.fromJson<String>(json['accountId']),
      storeId: serializer.fromJson<String>(json['storeId']),
      payload: serializer.fromJson<String>(json['payload']),
      effect: serializer.fromJson<String>(json['effect']),
      status: serializer.fromJson<String>(json['status']),
      error: serializer.fromJson<String?>(json['error']),
      resolution: serializer.fromJson<String?>(json['resolution']),
      resolvedAt: serializer.fromJson<DateTime?>(json['resolvedAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sequence': serializer.toJson<int>(sequence),
      'operationId': serializer.toJson<String>(operationId),
      'accountId': serializer.toJson<String>(accountId),
      'storeId': serializer.toJson<String>(storeId),
      'payload': serializer.toJson<String>(payload),
      'effect': serializer.toJson<String>(effect),
      'status': serializer.toJson<String>(status),
      'error': serializer.toJson<String?>(error),
      'resolution': serializer.toJson<String?>(resolution),
      'resolvedAt': serializer.toJson<DateTime?>(resolvedAt),
      'attempts': serializer.toJson<int>(attempts),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  OutboxRow copyWith({
    int? sequence,
    String? operationId,
    String? accountId,
    String? storeId,
    String? payload,
    String? effect,
    String? status,
    Value<String?> error = const Value.absent(),
    Value<String?> resolution = const Value.absent(),
    Value<DateTime?> resolvedAt = const Value.absent(),
    int? attempts,
    DateTime? createdAt,
  }) => OutboxRow(
    sequence: sequence ?? this.sequence,
    operationId: operationId ?? this.operationId,
    accountId: accountId ?? this.accountId,
    storeId: storeId ?? this.storeId,
    payload: payload ?? this.payload,
    effect: effect ?? this.effect,
    status: status ?? this.status,
    error: error.present ? error.value : this.error,
    resolution: resolution.present ? resolution.value : this.resolution,
    resolvedAt: resolvedAt.present ? resolvedAt.value : this.resolvedAt,
    attempts: attempts ?? this.attempts,
    createdAt: createdAt ?? this.createdAt,
  );
  OutboxRow copyWithCompanion(OutboxRowsCompanion data) {
    return OutboxRow(
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      storeId: data.storeId.present ? data.storeId.value : this.storeId,
      payload: data.payload.present ? data.payload.value : this.payload,
      effect: data.effect.present ? data.effect.value : this.effect,
      status: data.status.present ? data.status.value : this.status,
      error: data.error.present ? data.error.value : this.error,
      resolution: data.resolution.present
          ? data.resolution.value
          : this.resolution,
      resolvedAt: data.resolvedAt.present
          ? data.resolvedAt.value
          : this.resolvedAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxRow(')
          ..write('sequence: $sequence, ')
          ..write('operationId: $operationId, ')
          ..write('accountId: $accountId, ')
          ..write('storeId: $storeId, ')
          ..write('payload: $payload, ')
          ..write('effect: $effect, ')
          ..write('status: $status, ')
          ..write('error: $error, ')
          ..write('resolution: $resolution, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('attempts: $attempts, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sequence,
    operationId,
    accountId,
    storeId,
    payload,
    effect,
    status,
    error,
    resolution,
    resolvedAt,
    attempts,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxRow &&
          other.sequence == this.sequence &&
          other.operationId == this.operationId &&
          other.accountId == this.accountId &&
          other.storeId == this.storeId &&
          other.payload == this.payload &&
          other.effect == this.effect &&
          other.status == this.status &&
          other.error == this.error &&
          other.resolution == this.resolution &&
          other.resolvedAt == this.resolvedAt &&
          other.attempts == this.attempts &&
          other.createdAt == this.createdAt);
}

class OutboxRowsCompanion extends UpdateCompanion<OutboxRow> {
  final Value<int> sequence;
  final Value<String> operationId;
  final Value<String> accountId;
  final Value<String> storeId;
  final Value<String> payload;
  final Value<String> effect;
  final Value<String> status;
  final Value<String?> error;
  final Value<String?> resolution;
  final Value<DateTime?> resolvedAt;
  final Value<int> attempts;
  final Value<DateTime> createdAt;
  const OutboxRowsCompanion({
    this.sequence = const Value.absent(),
    this.operationId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.storeId = const Value.absent(),
    this.payload = const Value.absent(),
    this.effect = const Value.absent(),
    this.status = const Value.absent(),
    this.error = const Value.absent(),
    this.resolution = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  OutboxRowsCompanion.insert({
    this.sequence = const Value.absent(),
    required String operationId,
    required String accountId,
    required String storeId,
    required String payload,
    required String effect,
    this.status = const Value.absent(),
    this.error = const Value.absent(),
    this.resolution = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : operationId = Value(operationId),
       accountId = Value(accountId),
       storeId = Value(storeId),
       payload = Value(payload),
       effect = Value(effect);
  static Insertable<OutboxRow> custom({
    Expression<int>? sequence,
    Expression<String>? operationId,
    Expression<String>? accountId,
    Expression<String>? storeId,
    Expression<String>? payload,
    Expression<String>? effect,
    Expression<String>? status,
    Expression<String>? error,
    Expression<String>? resolution,
    Expression<DateTime>? resolvedAt,
    Expression<int>? attempts,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (sequence != null) 'sequence': sequence,
      if (operationId != null) 'operation_id': operationId,
      if (accountId != null) 'account_id': accountId,
      if (storeId != null) 'store_id': storeId,
      if (payload != null) 'payload': payload,
      if (effect != null) 'effect': effect,
      if (status != null) 'status': status,
      if (error != null) 'error': error,
      if (resolution != null) 'resolution': resolution,
      if (resolvedAt != null) 'resolved_at': resolvedAt,
      if (attempts != null) 'attempts': attempts,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  OutboxRowsCompanion copyWith({
    Value<int>? sequence,
    Value<String>? operationId,
    Value<String>? accountId,
    Value<String>? storeId,
    Value<String>? payload,
    Value<String>? effect,
    Value<String>? status,
    Value<String?>? error,
    Value<String?>? resolution,
    Value<DateTime?>? resolvedAt,
    Value<int>? attempts,
    Value<DateTime>? createdAt,
  }) {
    return OutboxRowsCompanion(
      sequence: sequence ?? this.sequence,
      operationId: operationId ?? this.operationId,
      accountId: accountId ?? this.accountId,
      storeId: storeId ?? this.storeId,
      payload: payload ?? this.payload,
      effect: effect ?? this.effect,
      status: status ?? this.status,
      error: error ?? this.error,
      resolution: resolution ?? this.resolution,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      attempts: attempts ?? this.attempts,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (storeId.present) {
      map['store_id'] = Variable<String>(storeId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (effect.present) {
      map['effect'] = Variable<String>(effect.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (resolution.present) {
      map['resolution'] = Variable<String>(resolution.value);
    }
    if (resolvedAt.present) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxRowsCompanion(')
          ..write('sequence: $sequence, ')
          ..write('operationId: $operationId, ')
          ..write('accountId: $accountId, ')
          ..write('storeId: $storeId, ')
          ..write('payload: $payload, ')
          ..write('effect: $effect, ')
          ..write('status: $status, ')
          ..write('error: $error, ')
          ..write('resolution: $resolution, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('attempts: $attempts, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $DraftRowsTable extends DraftRows
    with TableInfo<$DraftRowsTable, DraftRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DraftRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _storeIdMeta = const VerificationMeta(
    'storeId',
  );
  @override
  late final GeneratedColumn<String> storeId = GeneratedColumn<String>(
    'store_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [accountId, storeId, key, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'draft_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<DraftRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('store_id')) {
      context.handle(
        _storeIdMeta,
        storeId.isAcceptableOrUnknown(data['store_id']!, _storeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_storeIdMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, storeId, key};
  @override
  DraftRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DraftRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      storeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $DraftRowsTable createAlias(String alias) {
    return $DraftRowsTable(attachedDatabase, alias);
  }
}

class DraftRow extends DataClass implements Insertable<DraftRow> {
  final String accountId;
  final String storeId;
  final String key;
  final String payload;
  const DraftRow({
    required this.accountId,
    required this.storeId,
    required this.key,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['store_id'] = Variable<String>(storeId);
    map['key'] = Variable<String>(key);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  DraftRowsCompanion toCompanion(bool nullToAbsent) {
    return DraftRowsCompanion(
      accountId: Value(accountId),
      storeId: Value(storeId),
      key: Value(key),
      payload: Value(payload),
    );
  }

  factory DraftRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DraftRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      storeId: serializer.fromJson<String>(json['storeId']),
      key: serializer.fromJson<String>(json['key']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'storeId': serializer.toJson<String>(storeId),
      'key': serializer.toJson<String>(key),
      'payload': serializer.toJson<String>(payload),
    };
  }

  DraftRow copyWith({
    String? accountId,
    String? storeId,
    String? key,
    String? payload,
  }) => DraftRow(
    accountId: accountId ?? this.accountId,
    storeId: storeId ?? this.storeId,
    key: key ?? this.key,
    payload: payload ?? this.payload,
  );
  DraftRow copyWithCompanion(DraftRowsCompanion data) {
    return DraftRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      storeId: data.storeId.present ? data.storeId.value : this.storeId,
      key: data.key.present ? data.key.value : this.key,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DraftRow(')
          ..write('accountId: $accountId, ')
          ..write('storeId: $storeId, ')
          ..write('key: $key, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, storeId, key, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DraftRow &&
          other.accountId == this.accountId &&
          other.storeId == this.storeId &&
          other.key == this.key &&
          other.payload == this.payload);
}

class DraftRowsCompanion extends UpdateCompanion<DraftRow> {
  final Value<String> accountId;
  final Value<String> storeId;
  final Value<String> key;
  final Value<String> payload;
  final Value<int> rowid;
  const DraftRowsCompanion({
    this.accountId = const Value.absent(),
    this.storeId = const Value.absent(),
    this.key = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DraftRowsCompanion.insert({
    required String accountId,
    required String storeId,
    required String key,
    required String payload,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       storeId = Value(storeId),
       key = Value(key),
       payload = Value(payload);
  static Insertable<DraftRow> custom({
    Expression<String>? accountId,
    Expression<String>? storeId,
    Expression<String>? key,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (storeId != null) 'store_id': storeId,
      if (key != null) 'key': key,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DraftRowsCompanion copyWith({
    Value<String>? accountId,
    Value<String>? storeId,
    Value<String>? key,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return DraftRowsCompanion(
      accountId: accountId ?? this.accountId,
      storeId: storeId ?? this.storeId,
      key: key ?? this.key,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (storeId.present) {
      map['store_id'] = Variable<String>(storeId.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DraftRowsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('storeId: $storeId, ')
          ..write('key: $key, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CacheEntriesTable cacheEntries = $CacheEntriesTable(this);
  late final $OutboxRowsTable outboxRows = $OutboxRowsTable(this);
  late final $DraftRowsTable draftRows = $DraftRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cacheEntries,
    outboxRows,
    draftRows,
  ];
}

typedef $$CacheEntriesTableCreateCompanionBuilder =
    CacheEntriesCompanion Function({
      required String accountId,
      required String storeId,
      required String resource,
      required String entityId,
      required String payload,
      Value<int> rowid,
    });
typedef $$CacheEntriesTableUpdateCompanionBuilder =
    CacheEntriesCompanion Function({
      Value<String> accountId,
      Value<String> storeId,
      Value<String> resource,
      Value<String> entityId,
      Value<String> payload,
      Value<int> rowid,
    });

class $$CacheEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resource => $composableBuilder(
    column: $table.resource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CacheEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resource => $composableBuilder(
    column: $table.resource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CacheEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get storeId =>
      $composableBuilder(column: $table.storeId, builder: (column) => column);

  GeneratedColumn<String> get resource =>
      $composableBuilder(column: $table.resource, builder: (column) => column);

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$CacheEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CacheEntriesTable,
          CacheEntry,
          $$CacheEntriesTableFilterComposer,
          $$CacheEntriesTableOrderingComposer,
          $$CacheEntriesTableAnnotationComposer,
          $$CacheEntriesTableCreateCompanionBuilder,
          $$CacheEntriesTableUpdateCompanionBuilder,
          (
            CacheEntry,
            BaseReferences<_$AppDatabase, $CacheEntriesTable, CacheEntry>,
          ),
          CacheEntry,
          PrefetchHooks Function()
        > {
  $$CacheEntriesTableTableManager(_$AppDatabase db, $CacheEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CacheEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CacheEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CacheEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> storeId = const Value.absent(),
                Value<String> resource = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CacheEntriesCompanion(
                accountId: accountId,
                storeId: storeId,
                resource: resource,
                entityId: entityId,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String storeId,
                required String resource,
                required String entityId,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => CacheEntriesCompanion.insert(
                accountId: accountId,
                storeId: storeId,
                resource: resource,
                entityId: entityId,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CacheEntriesTable, CacheEntry>(table),
                  BaseReferences<_$AppDatabase, $CacheEntriesTable, CacheEntry>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CacheEntriesTable,
      CacheEntry,
      $$CacheEntriesTableFilterComposer,
      $$CacheEntriesTableOrderingComposer,
      $$CacheEntriesTableAnnotationComposer,
      $$CacheEntriesTableCreateCompanionBuilder,
      $$CacheEntriesTableUpdateCompanionBuilder,
      (
        CacheEntry,
        BaseReferences<_$AppDatabase, $CacheEntriesTable, CacheEntry>,
      ),
      CacheEntry,
      PrefetchHooks Function()
    >;
typedef $$OutboxRowsTableCreateCompanionBuilder = OutboxRowsCompanion Function({
  Value<int> sequence,
  required String operationId,
  required String accountId,
  required String storeId,
  required String payload,
  required String effect,
  Value<String> status,
  Value<String?> error,
  Value<String?> resolution,
  Value<DateTime?> resolvedAt,
  Value<int> attempts,
  Value<DateTime> createdAt,
});
typedef $$OutboxRowsTableUpdateCompanionBuilder = OutboxRowsCompanion Function({
  Value<int> sequence,
  Value<String> operationId,
  Value<String> accountId,
  Value<String> storeId,
  Value<String> payload,
  Value<String> effect,
  Value<String> status,
  Value<String?> error,
  Value<String?> resolution,
  Value<DateTime?> resolvedAt,
  Value<int> attempts,
  Value<DateTime> createdAt,
});

class $$OutboxRowsTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxRowsTable> {
  $$OutboxRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get effect => $composableBuilder(
    column: $table.effect,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resolution => $composableBuilder(
    column: $table.resolution,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxRowsTable> {
  $$OutboxRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get effect => $composableBuilder(
    column: $table.effect,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resolution => $composableBuilder(
    column: $table.resolution,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxRowsTable> {
  $$OutboxRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get storeId =>
      $composableBuilder(column: $table.storeId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get effect =>
      $composableBuilder(column: $table.effect, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<String> get resolution => $composableBuilder(
    column: $table.resolution,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$OutboxRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboxRowsTable,
          OutboxRow,
          $$OutboxRowsTableFilterComposer,
          $$OutboxRowsTableOrderingComposer,
          $$OutboxRowsTableAnnotationComposer,
          $$OutboxRowsTableCreateCompanionBuilder,
          $$OutboxRowsTableUpdateCompanionBuilder,
          (
            OutboxRow,
            BaseReferences<_$AppDatabase, $OutboxRowsTable, OutboxRow>,
          ),
          OutboxRow,
          PrefetchHooks Function()
        > {
  $$OutboxRowsTableTableManager(_$AppDatabase db, $OutboxRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> sequence = const Value.absent(),
                Value<String> operationId = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> storeId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String> effect = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<String?> resolution = const Value.absent(),
                Value<DateTime?> resolvedAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => OutboxRowsCompanion(
                sequence: sequence,
                operationId: operationId,
                accountId: accountId,
                storeId: storeId,
                payload: payload,
                effect: effect,
                status: status,
                error: error,
                resolution: resolution,
                resolvedAt: resolvedAt,
                attempts: attempts,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> sequence = const Value.absent(),
                required String operationId,
                required String accountId,
                required String storeId,
                required String payload,
                required String effect,
                Value<String> status = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<String?> resolution = const Value.absent(),
                Value<DateTime?> resolvedAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => OutboxRowsCompanion.insert(
                sequence: sequence,
                operationId: operationId,
                accountId: accountId,
                storeId: storeId,
                payload: payload,
                effect: effect,
                status: status,
                error: error,
                resolution: resolution,
                resolvedAt: resolvedAt,
                attempts: attempts,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutboxRowsTable, OutboxRow>(table),
                  BaseReferences<_$AppDatabase, $OutboxRowsTable, OutboxRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboxRowsTable,
      OutboxRow,
      $$OutboxRowsTableFilterComposer,
      $$OutboxRowsTableOrderingComposer,
      $$OutboxRowsTableAnnotationComposer,
      $$OutboxRowsTableCreateCompanionBuilder,
      $$OutboxRowsTableUpdateCompanionBuilder,
      (OutboxRow, BaseReferences<_$AppDatabase, $OutboxRowsTable, OutboxRow>),
      OutboxRow,
      PrefetchHooks Function()
    >;
typedef $$DraftRowsTableCreateCompanionBuilder = DraftRowsCompanion Function({
  required String accountId,
  required String storeId,
  required String key,
  required String payload,
  Value<int> rowid,
});
typedef $$DraftRowsTableUpdateCompanionBuilder = DraftRowsCompanion Function({
  Value<String> accountId,
  Value<String> storeId,
  Value<String> key,
  Value<String> payload,
  Value<int> rowid,
});

class $$DraftRowsTableFilterComposer
    extends Composer<_$AppDatabase, $DraftRowsTable> {
  $$DraftRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DraftRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $DraftRowsTable> {
  $$DraftRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DraftRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DraftRowsTable> {
  $$DraftRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get storeId =>
      $composableBuilder(column: $table.storeId, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$DraftRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DraftRowsTable,
          DraftRow,
          $$DraftRowsTableFilterComposer,
          $$DraftRowsTableOrderingComposer,
          $$DraftRowsTableAnnotationComposer,
          $$DraftRowsTableCreateCompanionBuilder,
          $$DraftRowsTableUpdateCompanionBuilder,
          (DraftRow, BaseReferences<_$AppDatabase, $DraftRowsTable, DraftRow>),
          DraftRow,
          PrefetchHooks Function()
        > {
  $$DraftRowsTableTableManager(_$AppDatabase db, $DraftRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DraftRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DraftRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DraftRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> storeId = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DraftRowsCompanion(
                accountId: accountId,
                storeId: storeId,
                key: key,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String storeId,
                required String key,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => DraftRowsCompanion.insert(
                accountId: accountId,
                storeId: storeId,
                key: key,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DraftRowsTable, DraftRow>(table),
                  BaseReferences<_$AppDatabase, $DraftRowsTable, DraftRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DraftRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DraftRowsTable,
      DraftRow,
      $$DraftRowsTableFilterComposer,
      $$DraftRowsTableOrderingComposer,
      $$DraftRowsTableAnnotationComposer,
      $$DraftRowsTableCreateCompanionBuilder,
      $$DraftRowsTableUpdateCompanionBuilder,
      (DraftRow, BaseReferences<_$AppDatabase, $DraftRowsTable, DraftRow>),
      DraftRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CacheEntriesTableTableManager get cacheEntries =>
      $$CacheEntriesTableTableManager(_db, _db.cacheEntries);
  $$OutboxRowsTableTableManager get outboxRows =>
      $$OutboxRowsTableTableManager(_db, _db.outboxRows);
  $$DraftRowsTableTableManager get draftRows =>
      $$DraftRowsTableTableManager(_db, _db.draftRows);
}

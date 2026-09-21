// GENERATED from contracts/openapi/biobalance.json. Do not edit.

class MoneyDto {
  final String currency;
  final String millimes;
  const MoneyDto({required this.currency, required this.millimes});
  factory MoneyDto.fromJson(Map<String, dynamic> json) => MoneyDto(
    currency: json['currency'] as String,
    millimes: json['millimes'] as String,
  );
  Map<String, dynamic> toJson() => {'currency': currency, 'millimes': millimes};
}

class UserDto {
  final String id;
  final String email;
  final String name;
  final bool platformAdmin;
  const UserDto({
    required this.id,
    required this.email,
    required this.name,
    required this.platformAdmin,
  });
  factory UserDto.fromJson(Map<String, dynamic> json) => UserDto(
    id: json['id'] as String,
    email: json['email'] as String,
    name: json['name'] as String,
    platformAdmin: json['platformAdmin'] as bool,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'platformAdmin': platformAdmin,
  };
}

class LoginRequestDto {
  final String email;
  final String password;
  final String? otp;
  const LoginRequestDto({
    required this.email,
    required this.password,
    this.otp,
  });
  factory LoginRequestDto.fromJson(Map<String, dynamic> json) =>
      LoginRequestDto(
        email: json['email'] as String,
        password: json['password'] as String,
        otp: json['otp'] == null ? null : json['otp'] as String,
      );
  Map<String, dynamic> toJson() => {
    'email': email,
    'password': password,
    if (otp != null) 'otp': otp,
  };
}

class LoginResponseDto {
  final String token;
  final String expiresAt;
  final UserDto user;
  const LoginResponseDto({
    required this.token,
    required this.expiresAt,
    required this.user,
  });
  factory LoginResponseDto.fromJson(Map<String, dynamic> json) =>
      LoginResponseDto(
        token: json['token'] as String,
        expiresAt: json['expiresAt'] as String,
        user: UserDto.fromJson(Map<String, dynamic>.from(json['user'])),
      );
  Map<String, dynamic> toJson() => {
    'token': token,
    'expiresAt': expiresAt,
    'user': user.toJson(),
  };
}

class StoreDto {
  final String id;
  final String organizationId;
  final String name;
  final String address;
  final String city;
  final String timezone;
  final List<dynamic> permissions;
  const StoreDto({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.address,
    required this.city,
    required this.timezone,
    required this.permissions,
  });
  factory StoreDto.fromJson(Map<String, dynamic> json) => StoreDto(
    id: json['id'] as String,
    organizationId: json['organizationId'] as String,
    name: json['name'] as String,
    address: json['address'] as String,
    city: json['city'] as String,
    timezone: json['timezone'] as String,
    permissions: List<dynamic>.from(json['permissions']),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'organizationId': organizationId,
    'name': name,
    'address': address,
    'city': city,
    'timezone': timezone,
    'permissions': permissions,
  };
}

class SyncOperationDto {
  final String operationId;
  final String storeId;
  final String organizationId;
  final double payloadVersion;
  final int? expectedVersion;
  final dynamic command;
  const SyncOperationDto({
    required this.operationId,
    required this.storeId,
    required this.organizationId,
    required this.payloadVersion,
    this.expectedVersion,
    required this.command,
  });
  factory SyncOperationDto.fromJson(Map<String, dynamic> json) =>
      SyncOperationDto(
        operationId: json['operationId'] as String,
        storeId: json['storeId'] as String,
        organizationId: json['organizationId'] as String,
        payloadVersion: (json['payloadVersion'] as num).toDouble(),
        expectedVersion: json['expectedVersion'] == null
            ? null
            : (json['expectedVersion'] as num).toInt(),
        command: json['command'],
      );
  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'storeId': storeId,
    'organizationId': organizationId,
    'payloadVersion': payloadVersion,
    if (expectedVersion != null) 'expectedVersion': expectedVersion,
    'command': command,
  };
}

class SyncBatchDto {
  final List<dynamic> operations;
  const SyncBatchDto({required this.operations});
  factory SyncBatchDto.fromJson(Map<String, dynamic> json) =>
      SyncBatchDto(operations: List<dynamic>.from(json['operations']));
  Map<String, dynamic> toJson() => {'operations': operations};
}

class SyncResultDto {
  final String operationId;
  final String status;
  final String? code;
  final String? message;
  final Map<String, dynamic>? data;
  const SyncResultDto({
    required this.operationId,
    required this.status,
    this.code,
    this.message,
    this.data,
  });
  factory SyncResultDto.fromJson(Map<String, dynamic> json) => SyncResultDto(
    operationId: json['operationId'] as String,
    status: json['status'] as String,
    code: json['code'] == null ? null : json['code'] as String,
    message: json['message'] == null ? null : json['message'] as String,
    data: json['data'] == null ? null : Map<String, dynamic>.from(json['data']),
  );
  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'status': status,
    if (code != null) 'code': code,
    if (message != null) 'message': message,
    if (data != null) 'data': data,
  };
}

class SyncResponseDto {
  final List<dynamic> results;
  const SyncResponseDto({required this.results});
  factory SyncResponseDto.fromJson(Map<String, dynamic> json) =>
      SyncResponseDto(results: List<dynamic>.from(json['results']));
  Map<String, dynamic> toJson() => {'results': results};
}

class SaleSubmissionDto {
  final String operationId;
  final String storeId;
  final String saleId;
  final String status;
  const SaleSubmissionDto({
    required this.operationId,
    required this.storeId,
    required this.saleId,
    required this.status,
  });
  factory SaleSubmissionDto.fromJson(Map<String, dynamic> json) =>
      SaleSubmissionDto(
        operationId: json['operationId'] as String,
        storeId: json['storeId'] as String,
        saleId: json['saleId'] as String,
        status: json['status'] as String,
      );
  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'storeId': storeId,
    'saleId': saleId,
    'status': status,
  };
}

class SaleRevisionDto {
  final String id;
  final String saleId;
  final int version;
  final String editorId;
  final String reason;
  final Map<String, dynamic>? before;
  final Map<String, dynamic> after;
  final String operationId;
  final String createdAt;
  const SaleRevisionDto({
    required this.id,
    required this.saleId,
    required this.version,
    required this.editorId,
    required this.reason,
    this.before,
    required this.after,
    required this.operationId,
    required this.createdAt,
  });
  factory SaleRevisionDto.fromJson(Map<String, dynamic> json) =>
      SaleRevisionDto(
        id: json['id'] as String,
        saleId: json['saleId'] as String,
        version: (json['version'] as num).toInt(),
        editorId: json['editorId'] as String,
        reason: json['reason'] as String,
        before: json['before'] == null
            ? null
            : Map<String, dynamic>.from(json['before']),
        after: Map<String, dynamic>.from(json['after']),
        operationId: json['operationId'] as String,
        createdAt: json['createdAt'] as String,
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'saleId': saleId,
    'version': version,
    'editorId': editorId,
    'reason': reason,
    if (before != null) 'before': before,
    'after': after,
    'operationId': operationId,
    'createdAt': createdAt,
  };
}

class DeliveryReceiptDto {
  final String id;
  final String deliveryId;
  final String actorId;
  final String operationId;
  final List<dynamic> lines;
  final Map<String, dynamic> differences;
  const DeliveryReceiptDto({
    required this.id,
    required this.deliveryId,
    required this.actorId,
    required this.operationId,
    required this.lines,
    required this.differences,
  });
  factory DeliveryReceiptDto.fromJson(Map<String, dynamic> json) =>
      DeliveryReceiptDto(
        id: json['id'] as String,
        deliveryId: json['deliveryId'] as String,
        actorId: json['actorId'] as String,
        operationId: json['operationId'] as String,
        lines: List<dynamic>.from(json['lines']),
        differences: Map<String, dynamic>.from(json['differences']),
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'deliveryId': deliveryId,
    'actorId': actorId,
    'operationId': operationId,
    'lines': lines,
    'differences': differences,
  };
}

class RewardClaimDto {
  final String id;
  final String storeId;
  final String userId;
  final String rewardId;
  final String title;
  final int cost;
  final String status;
  final int version;
  final String? productId;
  final int quantity;
  const RewardClaimDto({
    required this.id,
    required this.storeId,
    required this.userId,
    required this.rewardId,
    required this.title,
    required this.cost,
    required this.status,
    required this.version,
    this.productId,
    required this.quantity,
  });
  factory RewardClaimDto.fromJson(Map<String, dynamic> json) => RewardClaimDto(
    id: json['id'] as String,
    storeId: json['storeId'] as String,
    userId: json['userId'] as String,
    rewardId: json['rewardId'] as String,
    title: json['title'] as String,
    cost: (json['cost'] as num).toInt(),
    status: json['status'] as String,
    version: (json['version'] as num).toInt(),
    productId: json['productId'] == null ? null : json['productId'] as String,
    quantity: (json['quantity'] as num).toInt(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'storeId': storeId,
    'userId': userId,
    'rewardId': rewardId,
    'title': title,
    'cost': cost,
    'status': status,
    'version': version,
    if (productId != null) 'productId': productId,
    'quantity': quantity,
  };
}

class ApiErrorDto {
  final String code;
  final String message;
  final String? correlationId;
  const ApiErrorDto({
    required this.code,
    required this.message,
    this.correlationId,
  });
  factory ApiErrorDto.fromJson(Map<String, dynamic> json) => ApiErrorDto(
    code: json['code'] as String,
    message: json['message'] as String,
    correlationId: json['correlationId'] == null
        ? null
        : json['correlationId'] as String,
  );
  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    if (correlationId != null) 'correlationId': correlationId,
  };
}

// GENERATED transport contract decoder for real server fixtures.
import 'package:biobalance/data/services/api/generated/models.dart';

Object? decodeResponse(
  String operationId,
  Object? value,
) => switch (operationId) {
  "AdminOverview" => (() {
    final decoded = AdminOverviewResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "HealthHealth" => (() {
    final decoded = HealthHealthResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "IdentityLogin" => (() {
    final decoded = IdentityLoginResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "IdentityMe" => (() {
    final decoded = IdentityMeResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "IdentityLogout" => (() {
    final decoded = IdentityLogoutResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "IdentityInvite" => (() {
    final decoded = IdentityInviteResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "IdentityActivate" => (() {
    final decoded = IdentityActivateResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "IdentityForgot" => (() {
    final decoded = IdentityForgotResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "IdentityReset" => (() {
    final decoded = IdentityResetResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "WorkspaceOrganizations" => (() {
    final decoded = List.unmodifiable(
      (value as List).map(
        (item) =>
            OrganizationDto.fromJson(Map<String, dynamic>.from(item as Map)),
      ),
    );
    return decoded.map((item) => item.toJson()).toList();
  })(),
  "WorkspaceStores" => (() {
    final decoded = List.unmodifiable(
      (value as List).map(
        (item) =>
            StoreAccessDto.fromJson(Map<String, dynamic>.from(item as Map)),
      ),
    );
    return decoded.map((item) => item.toJson()).toList();
  })(),
  "WorkspaceCreate" => (() {
    final decoded = WorkspaceCreateResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "WorkspaceUpdateStore" => (() {
    final decoded = WorkspaceUpdateStoreResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "WorkspaceSnapshot" => (() {
    final decoded = WorkspaceSnapshotResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "WorkspaceSnapshotPage" => (() {
    final decoded = WorkspaceSnapshotPageResponseDto.fromJson(value);
    return decoded.toJson();
  })(),
  "WorkspaceCollection" => (() {
    final decoded = List.unmodifiable(
      (value as List).map((item) => CollectionItemDto.fromJson(item)),
    );
    return decoded.map((item) => item.toJson()).toList();
  })(),
  "WorkspaceHistory" => (() {
    final decoded = WorkspaceHistoryResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "WorkspaceFulfillment" => (() {
    final decoded = WorkspaceFulfillmentResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "WorkspaceSale" => (() {
    final decoded = WorkspaceSaleResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "WorkspaceChanges" => (() {
    final decoded = WorkspaceChangesResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "WorkspaceRanking" => (() {
    final decoded = WorkspaceRankingResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "WorkspaceConfig" => (() {
    final decoded = WorkspaceConfigResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "WorkspaceMember" => (() {
    final decoded = WorkspaceMemberResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "WorkspaceOnboarding" => (() {
    final decoded = WorkspaceOnboardingResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "WorkspaceReward" => (() {
    final decoded = WorkspaceRewardResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "CatalogSave" => (() {
    final decoded = CatalogSaveResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "CatalogImport" => (() {
    final decoded = CatalogImportResponseDto.fromJson(value);
    return decoded.toJson();
  })(),
  "OperationsStatus" => (() {
    final decoded = OperationsStatusResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "OperationsPush" => (() {
    final decoded = OperationsPushResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "NotificationsList" => (() {
    final decoded = List.unmodifiable(
      (value as List).map(
        (item) =>
            NotificationDto.fromJson(Map<String, dynamic>.from(item as Map)),
      ),
    );
    return decoded.map((item) => item.toJson()).toList();
  })(),
  "NotificationsRead" => (() {
    final decoded = NotificationsReadResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "NotificationsRemoveDevice" => (() {
    final decoded = NotificationsRemoveDeviceResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "NotificationsDevice" => (() {
    final decoded = NotificationsDeviceResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "NotificationsAnnounce" => (() {
    final decoded = NotificationsAnnounceResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "TrainingList" => (() {
    final decoded = List.unmodifiable(
      (value as List).map(
        (item) =>
            TrainingContentDto.fromJson(Map<String, dynamic>.from(item as Map)),
      ),
    );
    return decoded.map((item) => item.toJson()).toList();
  })(),
  "TrainingSave" => (() {
    final decoded = TrainingSaveResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "TrainingGet" => (() {
    final decoded = TrainingGetResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "TrainingStart" => (() {
    final decoded = TrainingStartResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "TrainingStatus" => (() {
    final decoded = TrainingStatusResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "TrainingChunk" => (() {
    final decoded = TrainingChunkResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "TrainingMetadata" => (() {
    final decoded = TrainingMetadataResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  "ReportingOverview" => (() {
    final decoded = ReportingOverviewResponseDto.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return decoded.toJson();
  })(),
  _ => throw FormatException('Unknown operation $operationId'),
};

-- Stable lifecycle command identities, including simultaneous actions in two groups.
CREATE UNIQUE INDEX "AuditEntry_lifecycle_operation_key" ON "AuditEntry"("operationId")
  WHERE action IN ('group.lifecycle','store.lifecycle');
CREATE INDEX "DeliveryIssue_open_order_idx" ON "DeliveryIssue"("orderId") WHERE status<>'resolved';

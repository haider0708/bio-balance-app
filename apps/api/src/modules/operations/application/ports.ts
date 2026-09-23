import {
  Actor,
  Scope,
  Lot,
  SaleRecord,
  PointsAccount,
  RewardRecord,
  ClaimRecord,
  OrderRecord,
  DeliveryRecord,
  OperationResult,
  DeliveryIssueRecord,
} from "../domain/contracts";
import { FulfillmentLine } from "../domain/order-fulfillment";
export interface Ledger {
  checkInventory(operationId?: string): Promise<void>;
  cursor(): Promise<string>;
  dependenciesAccepted(ids: string[]): Promise<boolean>;
  readonly scope: Scope;
  prior(id: string, hash: string): Promise<OperationResult | null>;
  finish(
    id: string,
    hash: string,
    result: OperationResult,
    entity: string,
    entityId: string,
    details: unknown,
  ): Promise<void>;
  lot(id: string): Promise<Lot>;
  lotsForProduct(productId: string, requiredUnits: number): Promise<Lot[]>;
  declareBatch(
    lotId: string,
    productId: string,
    batch: string,
    expiry: string,
  ): Promise<Lot>;
  receive(
    productId: string,
    batch: string,
    expiry: string,
    quantity: number,
    sourceId: string,
    operationId: string,
    reason: string,
    bucket?: "sellable" | "damaged",
  ): Promise<Lot>;
  move(
    lotId: string,
    quantity: number,
    sourceId: string,
    operationId: string,
    reason: string,
    bucket?: "sellable" | "damaged",
  ): Promise<void>;
  rate(productId: string): Promise<number>;
  sale(id: string): Promise<SaleRecord | null>;
  saveSale(
    sale: SaleRecord,
    previous: SaleRecord | undefined,
    reason: string,
    operationId: string,
  ): Promise<void>;
  points(userId: string): Promise<PointsAccount>;
  credit(
    userId: string,
    amount: bigint,
    kind: string,
    sourceId: string,
    operationId: string,
  ): Promise<void>;
  reserve(userId: string, delta: bigint): Promise<void>;
  reward(id: string): Promise<RewardRecord>;
  claim(id: string): Promise<ClaimRecord>;
  saveClaim(claim: ClaimRecord): Promise<void>;
  order(id: string): Promise<OrderRecord>;
  saveOrder(order: OrderRecord): Promise<void>;
  delivery(id: string): Promise<DeliveryRecord>;
  fulfillment(order: OrderRecord): Promise<FulfillmentLine[]>;
  saveDelivery(delivery: DeliveryRecord): Promise<void>;
  issue(deliveryId: string): Promise<DeliveryIssueRecord | null>;
  saveIssue(issue: DeliveryIssueRecord): Promise<void>;
  hasIssues(orderId: string): Promise<boolean>;
  receipt(
    deliveryId: string,
    lines: unknown,
    differences: unknown,
    operationId: string,
  ): Promise<void>;
  alerts(productIds: string[]): Promise<void>;
  notify(
    key: string,
    title: string,
    body: string,
    target?: { type: string; id: string },
  ): Promise<void>;
}
export abstract class UnitOfWork {
  abstract run<T>(
    actor: Actor,
    organizationId: string,
    storeId: string,
    work: (ledger: Ledger) => Promise<T>,
  ): Promise<T>;
}

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
  FlagRecord,
} from "../domain/contracts";
import { FulfillmentLine } from "../domain/order-fulfillment";
export interface Ledger {
  checkInventory(operationId?: string): Promise<void>;
  /** Runs work against a grossiste depot's stock, inside the same transaction. */
  inDepot<T>(
    depotStoreId: string,
    work: (depot: Ledger) => Promise<T>,
    options?: { allowInactive?: boolean },
  ): Promise<T>;
  /** True once the opening stock was declared (or declared absent). */
  openingClosed(): Promise<boolean>;
  closeOpening(): Promise<void>;
  /** Records a stock change in this store's synchronization feed. */
  touch(entity: string, entityId: string, changeId: string): Promise<void>;
  /** The active responsible account of a depot's organization. */
  owner(): Promise<string | null>;
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
  /** The points rate in force at the sale date (see PointsRateVersion). */
  rateAt(productId: string, at: Date): Promise<number>;
  /** The store's retail prices in force at a given moment. */
  listPrices(productIds: string[], at: Date): Promise<Map<string, bigint>>;
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
  orderProblemActive(orderId: string): Promise<boolean>;
  setOrderProblem(
    orderId: string,
    reason: string,
    active: boolean,
  ): Promise<void>;
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
    proof: { scanned: boolean; manualReason?: string },
  ): Promise<void>;
  /** Replaces a delivery's QR without touching the delivery itself. */
  renewTicket(deliveryId: string, ticketVersion: number): Promise<void>;
  saveFlag(flag: FlagRecord): Promise<void>;
  flag(id: string): Promise<FlagRecord>;
  decideFlag(flag: FlagRecord): Promise<void>;
  /** The delivery that last brought a lot into this store or depot. */
  lotSource(
    lotId: string,
  ): Promise<{ deliveryId: string; ticketNumber: string } | null>;
  /** The price each product is ordered at: wholesale for a depot, else supply. */
  supplyPrices(productIds: string[]): Promise<Map<string, bigint>>;
  /** The next delivery ticket number, BL-YYYY-NNNNNN. */
  nextTicketNumber(): Promise<string>;
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
    supplierStoreId?: string,
  ): Promise<T>;
}

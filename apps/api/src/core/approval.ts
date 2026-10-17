import type { Status } from "@prisma/client";
import { DomainError } from "./errors";

export type StatusAction =
  "approve" | "reject" | "suspend" | "reactivate" | "resubmit";

const transitions: Record<StatusAction, { from: Status[]; to: Status }> = {
  approve: { from: ["PENDING"], to: "ACTIVE" },
  reject: { from: ["PENDING"], to: "REJECTED" },
  suspend: { from: ["ACTIVE"], to: "SUSPENDED" },
  reactivate: { from: ["SUSPENDED"], to: "ACTIVE" },
  resubmit: { from: ["REJECTED"], to: "PENDING" },
};

/** The status an item moves to, or a clear error if that move is not allowed now. */
export function nextStatus(current: Status, action: StatusAction): Status {
  const rule = transitions[action];
  if (!rule.from.includes(current))
    throw new DomainError(
      "INVALID_STATE",
      `Cannot ${action} an item that is ${current.toLowerCase()}.`,
      409,
    );
  return rule.to;
}

/** After deciding, the admin may still change a decision for this long (payouts never). */
export const DECISION_WINDOW_MS = 6 * 3_600_000;

/** Whether a decision made at `at` can still be changed. */
export function withinDecisionWindow(at: Date | null, now = Date.now()) {
  return !!at && now - at.getTime() <= DECISION_WINDOW_MS;
}

/** Says why a decision can no longer be changed. */
export const decisionLocked = () =>
  new DomainError(
    "DECISION_LOCKED",
    "A decision can only be changed for 6 hours after it was made.",
    409,
  );

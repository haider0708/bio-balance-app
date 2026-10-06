import type { Status } from "@prisma/client";
import { DomainError } from "./errors";

export type StatusAction = "approve" | "reject" | "suspend" | "reactivate" | "resubmit";

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

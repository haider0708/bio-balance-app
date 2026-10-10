import { requireRule } from "../../core/errors";

/** A deleted account keeps its row for the records, under an address that can never receive mail. */
export const deletedEmail = (id: string) => `deleted-${id}@deleted.invalid`;

/** Nothing can bring a deleted account back: no reactivation, invitation or edit. */
export function refuseDeleted(user: { email: string }) {
  requireRule(
    !user.email.endsWith("@deleted.invalid"),
    "ACCOUNT_DELETED",
    "This account was deleted by its owner.",
    409,
  );
}

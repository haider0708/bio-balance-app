import type { Role } from "@prisma/client";
import type { Actor } from "./actor";

/** The people who work in a para: sellers and buyers. */
export const TEAM_ROLES: Role[] = ["VENDEUR", "ACHETEUR"];

export const isTeamRole = (role: Role) => TEAM_ROLES.includes(role);

/** Places and receives the orders of its para: a buyer, or a vendeur the responsable allowed. */
export const isBuyer = (actor: Pick<Actor, "role" | "canOrder">) =>
  actor.role === "ACHETEUR" || (actor.role === "VENDEUR" && !!actor.canOrder);

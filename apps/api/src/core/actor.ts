import type { Role } from "@prisma/client";

/** Who is calling: loaded fresh from the database on every request. */
export interface Actor {
  id: string;
  name: string;
  email: string;
  role: Role;
  /** Responsables and vendeurs. */
  regionId: string | null;
  /** Vendeurs. */
  pdvId: string | null;
  /** A vendeur who also places the orders of the para (switched on by the responsable). */
  canOrder?: boolean;
  /** Still on the generated password: nothing else works until they choose their own. */
  mustChangePassword?: boolean;
  locale: "fr" | "en";
  sessionId?: string;
}

/** Trusted server work (jobs, notifications) that acts for nobody in particular. */
export const SYSTEM = "SYSTEM" as const;

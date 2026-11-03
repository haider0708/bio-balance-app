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
  /**
   * Belongs to the test region (the store reviewers' accounts), or is the automation that runs it:
   * nothing they do reaches the real network, and no admin hears of it (see `notify`).
   */
  sandbox?: boolean;
  /** An admin who asked to see the test region (the app's "Show the test region" setting). */
  showSandbox?: boolean;
  /** Automation acting for this person (the test shop's seller): the alerts it causes are not pushed. */
  quietAlerts?: boolean;
}

/** Trusted server work (jobs, notifications) that acts for nobody in particular. */
export const SYSTEM = "SYSTEM" as const;

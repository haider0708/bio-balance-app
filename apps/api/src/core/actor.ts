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
  locale: "fr" | "en";
  sessionId?: string;
  /** Belongs to the test region (the store reviewers' accounts): nothing they do reaches the real network. */
  sandbox?: boolean;
  /** An admin who asked to see the test region (the app's "Show the test region" setting). */
  showSandbox?: boolean;
}

/** Trusted server work (jobs, notifications) that acts for nobody in particular. */
export const SYSTEM = "SYSTEM" as const;

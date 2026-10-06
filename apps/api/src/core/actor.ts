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
  /** Grossistes. */
  depotId: string | null;
  locale: "fr" | "en";
  sessionId?: string;
}

/** Trusted server work (jobs, notifications) that acts for nobody in particular. */
export const SYSTEM = "SYSTEM" as const;

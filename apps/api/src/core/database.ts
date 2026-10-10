import { Injectable, OnModuleDestroy } from "@nestjs/common";
import { PrismaPg } from "@prisma/adapter-pg";
import { Prisma, PrismaClient } from "@prisma/client";
import type { Actor } from "./actor";
import { SYSTEM } from "./actor";
import { DomainError } from "./errors";

export type Tx = Prisma.TransactionClient;

function retryable(error: unknown): boolean {
  if (error instanceof Error && error.name === "DriverAdapterError") {
    const cause = error.cause as { originalCode?: string } | undefined;
    return ["40001", "40P01"].includes(cause?.originalCode ?? "");
  }
  if (!(error instanceof Prisma.PrismaClientKnownRequestError)) return false;
  if (error.code === "P2034") return true;
  const cause = error.meta?.driverAdapterError as
    { cause?: { originalCode?: string } } | undefined;
  return (
    error.code === "P2010" &&
    ["40001", "40P01"].includes(
      String(error.meta?.code ?? cause?.cause?.originalCode),
    )
  );
}

/**
 * One PostgreSQL connection pool. Every business request runs in a single
 * transaction that first tells PostgreSQL who is calling (role, region, point
 * of sale, depot). The row-level security policies read those settings, so a
 * region can never touch another region's rows, whatever the query says.
 */
@Injectable()
export class Database extends PrismaClient implements OnModuleDestroy {
  constructor() {
    super({
      adapter: new PrismaPg({
        connectionString: process.env.DATABASE_URL,
        max: Number(process.env.DATABASE_POOL ?? 12),
      }),
    });
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }

  /** Run work as `actor` (or as trusted server code). Retried on serialization failures. */
  async run<T>(
    actor: Actor | typeof SYSTEM,
    work: (tx: Tx) => Promise<T>,
    isolationLevel: Prisma.TransactionIsolationLevel = "ReadCommitted",
  ): Promise<T> {
    for (let attempt = 0; ; attempt++) {
      try {
        return await this.$transaction(
          async (tx) => {
            if (actor === SYSTEM)
              await tx.$executeRaw`SELECT set_config('app.role','SYSTEM',true)`;
            else
              await tx.$executeRaw`SELECT set_config('app.role',${actor.role},true),
                set_config('app.user_id',${actor.id},true),
                set_config('app.region_id',${actor.regionId ?? ""},true),
                set_config('app.pdv_id',${actor.pdvId ?? ""},true)`;
            return work(tx);
          },
          { isolationLevel, maxWait: 5000, timeout: 15000 },
        );
      } catch (error) {
        if (retryable(error) && attempt < 3) {
          await new Promise((r) =>
            setTimeout(r, 20 * 2 ** attempt + Math.random() * 20),
          );
          continue;
        }
        if (retryable(error))
          throw new DomainError(
            "RETRY_LATER",
            "The system is busy. Try again.",
            503,
          );
        if (
          error instanceof Prisma.PrismaClientKnownRequestError &&
          error.code === "P2002"
        )
          throw new DomainError("DUPLICATE", "This already exists.", 409);
        throw error;
      }
    }
  }

  /** Lock one row so concurrent decisions on it queue up instead of racing. */
  async lock(tx: Tx, table: string, id: string) {
    if (!/^[A-Za-z]+$/.test(table)) throw new Error("INVALID_TABLE");
    const rows = await tx.$queryRawUnsafe<{ id: string }[]>(
      `SELECT id FROM "${table}" WHERE id = $1::uuid FOR UPDATE`,
      id,
    );
    return rows.length === 1;
  }
}

export const json = (value: unknown): Prisma.InputJsonValue =>
  JSON.parse(
    JSON.stringify(value, (_k, v) => (typeof v === "bigint" ? Number(v) : v)),
  );

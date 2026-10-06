import * as argon2 from "argon2";
import { DomainError } from "../../core/errors";

/** Admission control runs before Argon2 can queue work in libuv. */
export class PasswordHasher {
  private active = 0;
  constructor(private readonly capacity = 4) {}

  private async run<T>(work: () => Promise<T>): Promise<T> {
    if (this.active >= this.capacity)
      throw new DomainError(
        "AUTH_BUSY",
        "Sign-in is busy. Try again in a moment.",
        429,
        { retryAfterSeconds: 1 },
      );
    this.active++;
    try {
      return await work();
    } finally {
      this.active--;
    }
  }

  hash(password: string) {
    return this.run(() =>
      argon2.hash(password, {
        type: argon2.argon2id,
        memoryCost: 65536,
        timeCost: 3,
      }),
    );
  }

  verify(hash: string, password: string) {
    return this.run(() => argon2.verify(hash, password));
  }
}

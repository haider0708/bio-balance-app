import { Client } from "pg";

/**
 * Wakes the push loop the moment a notification is created: the database sends a signal on the
 * `notification_new` channel (a trigger, see the migration) to this one long-lived connection.
 * If the connection drops it reconnects by itself, and the loop still checks on a slow timer,
 * so a missed signal only ever costs a few seconds.
 */
export class NotificationSignal {
  private waiter?: () => void;
  private pending = false;
  private stopped = false;
  private client?: Client;
  /** True while the connection is listening. */
  listening = false;

  constructor(private readonly url: string) {}

  start() {
    void this.connect();
  }

  private async connect() {
    while (!this.stopped) {
      const client = new Client({
        connectionString: this.url,
        keepAlive: true,
      });
      try {
        client.on("error", () => undefined);
        client.on("notification", () => this.signal());
        await client.connect();
        await client.query("LISTEN notification_new");
        this.client = client;
        this.listening = true;
        // Anything created while the connection was down is picked up now.
        this.signal();
        await new Promise<void>((resolve) => client.once("end", resolve));
      } catch {
        // The database is unavailable: try again below.
      }
      this.listening = false;
      await client.end().catch(() => undefined);
      if (!this.stopped) await new Promise((r) => setTimeout(r, 2000));
    }
  }

  signal() {
    this.pending = true;
    this.waiter?.();
  }

  /** Resolves at the next signal, or after [timeoutMs]. A signal that came earlier counts. */
  async wait(timeoutMs: number) {
    if (!this.pending)
      await new Promise<void>((resolve) => {
        const done = () => {
          clearTimeout(timer);
          this.waiter = undefined;
          resolve();
        };
        const timer = setTimeout(done, timeoutMs);
        this.waiter = done;
      });
    this.pending = false;
  }

  async stop() {
    this.stopped = true;
    this.signal();
    await this.client?.end().catch(() => undefined);
  }
}

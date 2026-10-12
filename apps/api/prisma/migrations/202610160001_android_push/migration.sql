-- Android phones register a Firebase token next to the iPhones' Apple token.
ALTER TABLE "PushDevice" DROP CONSTRAINT "PushDevice_platform_check";
ALTER TABLE "PushDevice" DROP CONSTRAINT "PushDevice_token_check";
ALTER TABLE "PushDevice" ADD CONSTRAINT "PushDevice_platform_check" CHECK ("platform" IN ('IOS', 'ANDROID'));
ALTER TABLE "PushDevice" ADD CONSTRAINT "PushDevice_token_check" CHECK (
  ("platform" = 'IOS' AND "token" ~ '^[0-9a-f]{32,200}$')
  OR ("platform" = 'ANDROID' AND "token" ~ '^[A-Za-z0-9_:.-]+$' AND length("token") BETWEEN 40 AND 4096)
);

-- The worker listens on this channel, so a new notification reaches phones within milliseconds
-- instead of at the next timer tick. One signal per statement, however many rows it inserts.
CREATE FUNCTION notify_new_notification() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_notify('notification_new', '');
  RETURN NULL;
END; $$;
CREATE TRIGGER "Notification_push_signal" AFTER INSERT ON "Notification"
  FOR EACH STATEMENT EXECUTE FUNCTION notify_new_notification();

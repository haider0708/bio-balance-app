-- A new kind of account: the order manager (runs the supply side). The value is used from the next migration.
ALTER TYPE "Role" ADD VALUE IF NOT EXISTS 'ORDERS';

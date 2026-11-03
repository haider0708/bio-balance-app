/** Amounts are whole millimes (1 TND = 1000 millimes) so sums are always exact. */
export const MAX_MILLIMES = 1_000_000_000n; // 1 000 000 TND

/** A reward rate above this per unit must be confirmed (`confirmHigh`): it is more likely a typo. */
export const REWARD_CONFIRM_MILLIMES = 10_000n; // 10 TND per unit
/** No rate above this per unit is accepted. */
export const REWARD_CEILING_MILLIMES = 100_000n; // 100 TND per unit
/** One sale that earns more than this tells the admins at once. */
export const SALE_REWARD_ALERT_MILLIMES = 50_000n; // 50 TND

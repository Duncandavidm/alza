// Moneda de canje de un comercio aliado (partner_merchants.reward_currency).
// - "cashback": US$ ganados con facturas verificadas; los valores se guardan
//   en centavos (1 punto = US$0.01) y se muestran como dinero ("$3.50").
// - "puntos": puntos ganados por buenos habitos financieros; se guardan tal
//   cual (enteros) y se muestran como "150 pts".

import { formatCashback, num } from "./format";

export const REWARD_CURRENCIES = ["cashback", "puntos"] as const;
export type RewardCurrency = (typeof REWARD_CURRENCIES)[number];

export const REWARD_CURRENCY_LABELS: Record<RewardCurrency, string> = {
  cashback: "Con cashback (dólares de facturas)",
  puntos: "Con puntos (buenos hábitos)",
};

/// Normaliza cualquier valor a una moneda valida (por defecto "cashback").
export function toRewardCurrency(value: unknown): RewardCurrency {
  return value === "puntos" ? "puntos" : "cashback";
}

/// "$3.50" (cashback, valor en centavos) o "150 pts" (puntos).
export function formatRewardValue(value: number, currency: RewardCurrency): string {
  if (currency === "puntos") return `${Math.round(num(value)).toLocaleString("es-PA")} pts`;
  return formatCashback(value);
}

/// Version larga para frases: "$3.50 de cashback" o "150 puntos".
export function formatRewardValueLong(value: number, currency: RewardCurrency): string {
  if (currency === "puntos") {
    const points = Math.round(num(value));
    return `${points.toLocaleString("es-PA")} ${points === 1 ? "punto" : "puntos"}`;
  }
  return `${formatCashback(value)} de cashback`;
}

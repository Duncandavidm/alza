// Tipo de canjeable (migracion 0065): un producto, un % de descuento o un
// cupon de US$. Sin dependencias de servidor: lo usan el formulario
// (vista previa) y la accion que guarda.

export type RewardType = "producto" | "porcentaje" | "monto";

export const REWARD_TYPES: { value: RewardType; label: string }[] = [
  { value: "producto", label: "Producto (ej. un capuchino)" },
  { value: "porcentaje", label: "Descuento en % (ej. 10%)" },
  { value: "monto", label: "Cupón en US$ (ej. $20)" },
];

export function toRewardType(value: unknown): RewardType {
  return value === "porcentaje" || value === "monto" ? value : "producto";
}

function trimNumber(value: number): string {
  return Number.isInteger(value) ? String(value) : value.toFixed(2).replace(/0+$/, "").replace(/\.$/, "");
}

/// Nombre que se ve en la app y en caja cuando el comercio no escribe uno:
/// "10% de descuento" o "Cupón de $20".
export function defaultRewardName(type: RewardType, value: number | null): string {
  if (!value || !Number.isFinite(value) || value <= 0) return "";
  if (type === "porcentaje") return `${trimNumber(value)}% de descuento`;
  if (type === "monto") return `Cupón de $${value % 1 === 0 ? value : value.toFixed(2)}`;
  return "";
}

/// Etiqueta corta para tablas del panel.
export function rewardTypeLabel(type: RewardType): string {
  if (type === "porcentaje") return "Descuento %";
  if (type === "monto") return "Cupón US$";
  return "Producto";
}

export function isDiscountType(type: unknown): boolean {
  return type === "porcentaje" || type === "monto";
}

// ---------------------------------------------------------------------
// Descuento gratis "por ser de MonAvi" (migracion 0067)
// ---------------------------------------------------------------------

export type BenefitPeriod = "dia" | "semana" | "mes" | "siempre";

export const BENEFIT_PERIODS: { value: BenefitPeriod; label: string }[] = [
  { value: "semana", label: "por semana" },
  { value: "dia", label: "por día" },
  { value: "mes", label: "por mes" },
  { value: "siempre", label: "en total (una sola vez)" },
];

export function toBenefitPeriod(value: unknown): BenefitPeriod {
  return value === "dia" || value === "mes" || value === "siempre" ? value : "semana";
}

/// "1 vez por semana", "2 veces por mes", "1 vez en total".
export function benefitLimitLabel(limit: number | null | undefined, period: unknown): string {
  const times = Math.max(1, Number(limit ?? 1));
  const label = BENEFIT_PERIODS.find((entry) => entry.value === toBenefitPeriod(period))?.label ?? "por semana";
  return `${times} ${times === 1 ? "vez" : "veces"} ${label.replace(" (una sola vez)", "")}`;
}

// Helpers de formato. Los numeros de Postgres (numeric) pueden llegar
// como string o null via PostgREST: num() los normaliza.

export function num(value: unknown): number {
  if (value === null || value === undefined || value === "") return 0;
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function numOrNull(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

export function formatInt(value: unknown): string {
  return Math.round(num(value)).toLocaleString("es-PA");
}

export function formatMoney(value: unknown): string {
  const parsed = numOrNull(value);
  if (parsed === null) return "—";
  return `$${parsed.toLocaleString("es-PA", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

export function formatDecimal(value: unknown, digits = 1): string {
  const parsed = numOrNull(value);
  if (parsed === null) return "—";
  return parsed.toLocaleString("es-PA", { minimumFractionDigits: digits, maximumFractionDigits: digits });
}

export function formatPercent(value: unknown): string {
  const parsed = numOrNull(value);
  if (parsed === null) return "—";
  return `${parsed.toLocaleString("es-PA", { maximumFractionDigits: 1 })} %`;
}

export function formatPoints(value: unknown): string {
  return `${formatInt(value)} pts`;
}

export function formatDateTime(value: string | null | undefined): string {
  if (!value) return "—";
  return new Date(value).toLocaleString("es-PA", {
    timeZone: "America/Panama",
    dateStyle: "medium",
    timeStyle: "short",
  });
}

export function formatDate(value: string | null | undefined): string {
  if (!value) return "—";
  return new Date(value).toLocaleDateString("es-PA", { timeZone: "America/Panama", dateStyle: "medium" });
}

/// PostgREST devuelve una relacion embebida como objeto (FK a uno), pero
/// sin tipos generados TS la ve como arreglo; esto acepta ambas.
export function embedded<T>(value: T | T[] | null | undefined): T | null {
  if (!value) return null;
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

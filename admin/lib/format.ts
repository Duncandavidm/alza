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

/// Cashback: el ledger de puntos guarda enteros donde 1 punto = US$0.01
/// (la regla de 1 punto por dolar de factura = 1% de cashback). En el
/// panel SIEMPRE se muestra dinero, nunca "puntos": 350 -> "$3.50".
/// Sirve para reward_items.points_cost, reward_redemptions.points_cost,
/// points_awarded, presupuestos de ofertas, etc.
export function formatCashback(cents: unknown): string {
  return formatMoney(Math.round(num(cents)) / 100);
}

/// "3.50" (dolares, para un input) a partir de centavos.
export function centsToDollarInput(cents: unknown): string {
  return (Math.round(num(cents)) / 100).toFixed(2);
}

/// Convierte lo que se escribe en un campo "US$" (ej. "3.5", "3,50",
/// "$3.50") a centavos enteros. Devuelve null si no es un monto valido
/// mayor que 0 con maximo 2 decimales.
export function parseDollarsToCents(raw: string): number | null {
  const value = raw.trim().replace(/^\$/, "").replace(",", ".").trim();
  if (!/^\d{1,7}(\.\d{1,2})?$/.test(value)) return null;
  const cents = Math.round(Number(value) * 100);
  return Number.isInteger(cents) && cents > 0 ? cents : null;
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

import "server-only";
import { optionalText, parseHttpUrl, text } from "./validation";
import { centsToDollarInput, num, parseDollarsToCents } from "./format";
import { type RewardCurrency } from "./currency";

// Campañas de marcas (brand_campaigns, migracion 0038): una marca paga
// para que los clientes ganen un premio extra al comprar su producto.
// Las facturas DGI confirmadas se comparan con keywords; cada factura que
// aplica queda en campaign_conversions (lo que se le cobra a la marca).

export const CAMPAIGN_STATUSES = ["draft", "active", "paused", "ended", "budget_exhausted"] as const;
export type CampaignStatus = (typeof CAMPAIGN_STATUSES)[number];

export const CAMPAIGN_STATUS_LABELS: Record<CampaignStatus, string> = {
  draft: "borrador",
  active: "activa",
  paused: "pausada",
  ended: "terminada",
  budget_exhausted: "sin presupuesto",
};

export function toCampaignStatus(value: unknown): CampaignStatus {
  return (CAMPAIGN_STATUSES as readonly string[]).includes(String(value)) ? (value as CampaignStatus) : "draft";
}

export type Campaign = {
  id: string;
  brand: string;
  name: string;
  description: string | null;
  image_url: string | null;
  sponsor_contact: string | null;
  keywords: string[];
  merchant_rucs: string[] | null;
  bonus_currency: RewardCurrency;
  bonus_per_unit: number | null;
  bonus_percent: number | string | null;
  max_units_per_receipt: number;
  fee_per_conversion_cents: number | null;
  budget_total: number | null;
  budget_spent: number;
  starts_at: string;
  ends_at: string | null;
  status: CampaignStatus;
  created_at: string;
  updated_at: string;
};

export const CAMPAIGN_COLUMNS =
  "id, brand, name, description, image_url, sponsor_contact, keywords, merchant_rucs, bonus_currency, bonus_per_unit, bonus_percent, max_units_per_receipt, fee_per_conversion_cents, budget_total, budget_spent, starts_at, ends_at, status, created_at, updated_at";

export type CampaignFields = {
  brand: string;
  name: string;
  description: string | null;
  image_url: string | null;
  sponsor_contact: string | null;
  keywords: string[];
  merchant_rucs: string[] | null;
  bonus_currency: RewardCurrency;
  bonus_per_unit: number | null;
  bonus_percent: number | null;
  max_units_per_receipt: number;
  fee_per_conversion_cents: number | null;
  budget_total: number | null;
  starts_at: string;
  ends_at: string | null;
};

// ---------------------------------------------------------------------------
// Fechas: los formularios usan <input type="date"> en hora de Panama
// (UTC-5 todo el año, sin horario de verano).
// ---------------------------------------------------------------------------

const PANAMA_OFFSET = "-05:00";

/// "2026-11-07" (hora de Panama) a partir de un timestamptz.
export function toPanamaDateInput(value: string | null | undefined): string {
  if (!value) return "";
  return new Date(value).toLocaleDateString("en-CA", { timeZone: "America/Panama" });
}

function isValidDateInput(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T12:00:00${PANAMA_OFFSET}`);
  return !Number.isNaN(date.getTime()) && toPanamaDateInput(date.toISOString()) === value;
}

/// Inicio del dia en Panama.
function panamaStartOfDay(value: string): string {
  return new Date(`${value}T00:00:00${PANAMA_OFFSET}`).toISOString();
}

/// Fin = medianoche del dia siguiente en Panama (ends_at es exclusivo:
/// la campaña vale todo el dia que se eligio como "Fin").
function panamaEndOfDay(value: string): string {
  const start = new Date(`${value}T00:00:00${PANAMA_OFFSET}`);
  return new Date(start.getTime() + 24 * 60 * 60 * 1000).toISOString();
}

/// Valor para el campo "Fin" a partir de ends_at (el dia anterior a la
/// medianoche guardada).
export function endsAtToDateInput(value: string | null | undefined): string {
  if (!value) return "";
  return toPanamaDateInput(new Date(new Date(value).getTime() - 1000).toISOString());
}

// ---------------------------------------------------------------------------
// Valores del premio: puntos (enteros) o cashback (se escribe en US$ y se
// guarda en centavos).
// ---------------------------------------------------------------------------

/// Texto para un input a partir del valor guardado.
export function bonusValueToInput(value: number | null | undefined, currency: RewardCurrency): string {
  if (value === null || value === undefined) return "";
  return currency === "cashback" ? centsToDollarInput(value) : String(Math.round(num(value)));
}

function parsePositiveInt(raw: string, max = 1_000_000_000): number | null {
  if (!/^\d{1,10}$/.test(raw)) return null;
  const value = Number(raw);
  return Number.isInteger(value) && value > 0 && value <= max ? value : null;
}

function parseBonusValue(raw: string, currency: RewardCurrency): number | null {
  if (currency === "cashback") {
    const cents = parseDollarsToCents(raw);
    return cents !== null && cents <= 1_000_000_000 ? cents : null;
  }
  return parsePositiveInt(raw.replace(/[.,\s]/g, ""));
}

/// "coca cola, Coca-Cola ,  " -> ["coca cola", "coca-cola"]
export function parseList(raw: string, { lowercase }: { lowercase: boolean }): string[] {
  const seen = new Set<string>();
  for (const part of raw.split(/[,\n;]/)) {
    let value = part.trim().replace(/\s+/g, " ");
    if (lowercase) value = value.toLowerCase();
    if (value) seen.add(value.slice(0, 80));
  }
  return Array.from(seen);
}

/// Lee y valida los campos de la campaña desde el formulario del panel.
export function parseCampaignFields(formData: FormData): { fields?: CampaignFields; error?: string } {
  const brand = text(formData, "brand", 120);
  const name = text(formData, "name", 160);
  if (!brand) return { error: "La marca es obligatoria." };
  if (!name) return { error: "El nombre de la campaña es obligatorio." };

  const keywords = parseList(text(formData, "keywords", 2000), { lowercase: true });
  if (keywords.length === 0) {
    return { error: "Escribe al menos una palabra como sale en la factura (por ejemplo: coca cola, coca-cola)." };
  }
  if (keywords.length > 30) return { error: "Usa como máximo 30 palabras en la factura." };
  if (keywords.some((keyword) => keyword.length < 3)) {
    return { error: "Cada palabra en la factura debe tener al menos 3 letras, para no premiar productos de otras marcas." };
  }

  const rucs = parseList(text(formData, "merchant_rucs", 2000), { lowercase: false });
  if (rucs.some((ruc) => ruc.length > 40)) return { error: "Hay un RUC demasiado largo en Comercios." };

  const currencyRaw = text(formData, "bonus_currency", 20);
  if (currencyRaw !== "puntos" && currencyRaw !== "cashback") {
    return { error: "Elige la moneda del premio: puntos o cashback." };
  }
  const currency: RewardCurrency = currencyRaw;

  const perUnitRaw = text(formData, "bonus_per_unit", 20);
  const bonusPerUnit = perUnitRaw ? parseBonusValue(perUnitRaw, currency) : null;
  if (perUnitRaw && bonusPerUnit === null) {
    return {
      error:
        currency === "cashback"
          ? "El premio por unidad debe ser un monto en US$ mayor que $0 con máximo 2 decimales (ej. 0.25)."
          : "El premio por unidad debe ser un número entero de puntos mayor que 0 (ej. 50).",
    };
  }

  const percentRaw = text(formData, "bonus_percent", 20).replace(",", ".");
  let bonusPercent: number | null = null;
  if (percentRaw) {
    const value = Number(percentRaw);
    if (!/^\d{1,4}(\.\d{1,2})?$/.test(percentRaw) || !(value > 0) || value > 9999) {
      return { error: "El extra por cada dólar debe ser un número mayor que 0 con máximo 2 decimales (ej. 1)." };
    }
    bonusPercent = value;
  }

  if (bonusPerUnit === null && bonusPercent === null) {
    return { error: "Indica el premio: por unidad, extra por cada dólar, o ambos." };
  }

  const maxUnitsRaw = text(formData, "max_units_per_receipt", 10) || "5";
  const maxUnits = parsePositiveInt(maxUnitsRaw, 1000);
  if (maxUnits === null) return { error: "El máximo de unidades por factura debe ser un entero entre 1 y 1000." };

  const feeRaw = text(formData, "fee_per_conversion", 20);
  let feeCents: number | null = null;
  if (feeRaw) {
    if (/^\$?\s*0+([.,]0{1,2})?$/.test(feeRaw)) {
      feeCents = 0;
    } else {
      feeCents = parseDollarsToCents(feeRaw);
      if (feeCents === null) {
        return { error: "La tarifa por venta verificada debe ser un monto en US$ con máximo 2 decimales (ej. 0.50)." };
      }
    }
  }

  const budgetRaw = text(formData, "budget_total", 20);
  const budgetTotal = budgetRaw ? parseBonusValue(budgetRaw, currency) : null;
  if (budgetRaw && budgetTotal === null) {
    return {
      error:
        currency === "cashback"
          ? "El presupuesto de premios debe ser un monto en US$ mayor que $0 (ej. 500)."
          : "El presupuesto de premios debe ser un número entero de puntos mayor que 0 (ej. 100000).",
    };
  }

  const startsRaw = text(formData, "starts_at", 10);
  const endsRaw = text(formData, "ends_at", 10);
  if (!startsRaw || !isValidDateInput(startsRaw)) return { error: "Elige la fecha de inicio." };
  if (endsRaw && !isValidDateInput(endsRaw)) return { error: "La fecha de fin no es válida." };
  if (endsRaw && endsRaw < startsRaw) return { error: "La fecha de fin no puede ser antes del inicio." };

  const imageRaw = text(formData, "image_url", 600);
  const imageUrl = imageRaw ? parseHttpUrl(imageRaw) : null;
  if (imageRaw && !imageUrl) return { error: "La imagen debe ser un enlace que empiece con https://." };

  return {
    fields: {
      brand,
      name,
      description: optionalText(formData, "description", 300),
      image_url: imageUrl,
      sponsor_contact: optionalText(formData, "sponsor_contact", 200),
      keywords,
      merchant_rucs: rucs.length > 0 ? rucs : null,
      bonus_currency: currency,
      bonus_per_unit: bonusPerUnit,
      bonus_percent: bonusPercent,
      max_units_per_receipt: maxUnits,
      fee_per_conversion_cents: feeCents,
      budget_total: budgetTotal,
      starts_at: panamaStartOfDay(startsRaw),
      ends_at: endsRaw ? panamaEndOfDay(endsRaw) : null,
    },
  };
}

// ---------------------------------------------------------------------------
// Reporte (RPC brand_campaign_report)
// ---------------------------------------------------------------------------

type Num = number | string | null;

export type CampaignReport = {
  conversions: Num;
  people: Num;
  units: Num;
  sales: Num;
  bonus_given: Num;
  amount_due_cents: Num;
  by_merchant: { merchant: string | null; conversions: Num; people: Num; units: Num; sales: Num }[];
  by_week: { week: string | null; conversions: Num; units: Num; sales: Num }[];
};

export function normalizeCampaignReport(raw: unknown): CampaignReport {
  const data = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const list = <T,>(value: unknown): T[] => (Array.isArray(value) ? (value as T[]) : []);
  return {
    conversions: (data.conversions as Num) ?? 0,
    people: (data.people as Num) ?? 0,
    units: (data.units as Num) ?? 0,
    sales: (data.sales as Num) ?? 0,
    bonus_given: (data.bonus_given as Num) ?? 0,
    amount_due_cents: (data.amount_due_cents as Num) ?? 0,
    by_merchant: list(data.by_merchant),
    by_week: list(data.by_week),
  };
}

export function friendlyCampaignDbError(error: { code?: string; message: string }): string {
  if (error.code === "23514") return "Algún valor no es válido para la campaña (revisa el premio, el presupuesto y las fechas).";
  return error.message;
}

// Segmentos de clientes para notificaciones push y bonos/regalos.
// El JSON coincide con el que entiende segment_user_ids() (migracion
// 0040): todas las claves son opcionales. La base SIEMPRE limita el
// segmento a quienes dieron el consentimiento 'ofertas' (regla 4.5.4 de
// Apple: push promocional solo con permiso explicito).
//
// En los formularios del panel los campos van por GET (?gender=...&age=...)
// para que "Calcular alcance" sea un simple recargar la pagina.

import { parseDollarsToCents } from "./format";

export const SEGMENT_GENDERS = ["femenino", "masculino", "otro"] as const;
export const SEGMENT_AGES = ["18-24", "25-34", "35-44", "45-54", "55+"] as const;
export const SEGMENT_DAYS = [7, 14, 30, 60, 90, 180, 365] as const;
export const SEGMENT_ACTIVITIES = ["mas_activos", "menos_activos", "inactivos", "top_facturas", "mas_ahorro", "mas_ingresos"] as const;
export const SEGMENT_PAYMENTS = [
  "tarjeta", "credito", "debito", "efectivo", "yappy", "transferencia", "billetera", "cheque", "vale", "otro",
] as const;

export type SegmentGender = (typeof SEGMENT_GENDERS)[number];
export type SegmentAge = (typeof SEGMENT_AGES)[number];
export type SegmentActivity = (typeof SEGMENT_ACTIVITIES)[number];
export type SegmentPayment = (typeof SEGMENT_PAYMENTS)[number];

export type Segment = {
  gender?: SegmentGender;
  age_range?: SegmentAge;
  days?: number;
  activity?: SegmentActivity;
  min_receipts?: number;
  bought_product?: string;
  merchant_ruc?: string;
  payment?: SegmentPayment;
  min_cashback?: number;
  /// Ahorro minimo en metas (US$).
  min_savings?: number;
  /// Ingreso mensual promedio registrado, minimo y maximo (US$).
  min_income?: number;
  max_income?: number;
};

export const SEGMENT_GENDER_LABELS: Record<SegmentGender, string> = {
  femenino: "Mujeres",
  masculino: "Hombres",
  otro: "Otro",
};

export const SEGMENT_ACTIVITY_LABELS: Record<SegmentActivity, string> = {
  mas_activos: "Los que más usan la app (20 % más activo)",
  menos_activos: "Los que menos la usan (1 a 5 días con actividad)",
  inactivos: "Inactivos hace más de 14 días",
  top_facturas: "Los que más escanean facturas (20 % superior)",
  mas_ahorro: "Los que más ahorran (20 % con más ahorro en metas)",
  mas_ingresos: "Los de mayores ingresos (20 % con más ingreso mensual)",
};

export const SEGMENT_PAYMENT_LABELS: Record<SegmentPayment, string> = {
  tarjeta: "Tarjeta (crédito o débito)",
  credito: "Tarjeta de crédito",
  debito: "Tarjeta de débito / Clave",
  efectivo: "Efectivo",
  yappy: "Yappy",
  transferencia: "Transferencia / ACH / depósito",
  billetera: "Billetera digital (Yappy, Nequi…)",
  cheque: "Cheque",
  vale: "Vale, tarjeta de regalo o fidelización",
  otro: "Otro medio de pago",
};

/// Atajos de un clic (Bonos y regalos / Notificaciones).
export const SEGMENT_PRESETS: { activity: SegmentActivity; label: string }[] = [
  { activity: "mas_activos", label: "Los que más usan la app" },
  { activity: "top_facturas", label: "Los que más escanean facturas" },
  { activity: "menos_activos", label: "Los que menos la usan" },
  { activity: "inactivos", label: "Inactivos +14 días" },
  { activity: "mas_ahorro", label: "Los que más ahorran" },
  { activity: "mas_ingresos", label: "Los de mayores ingresos" },
];

/// Nombres de los campos del formulario (GET o FormData).
export const SEGMENT_FIELD_NAMES = [
  "gender",
  "age",
  "days",
  "activity",
  "min_receipts",
  "product",
  "ruc",
  "payment",
  "min_cashback",
  "min_savings",
  "min_income",
  "max_income",
  "preset",
] as const;

function oneOf<T extends string>(value: string | undefined, allowed: readonly T[]): T | undefined {
  return value && (allowed as readonly string[]).includes(value) ? (value as T) : undefined;
}

function cleanText(value: string | undefined, max: number): string | undefined {
  const text = (value ?? "").replace(/\s+/g, " ").trim().slice(0, max);
  return text || undefined;
}

/// Lee el segmento desde searchParams o FormData (get devuelve el texto
/// del campo). Ignora valores invalidos en vez de fallar.
export function parseSegment(get: (key: string) => string | undefined | null): Segment {
  const read = (key: string) => {
    const value = get(key);
    return value === null || value === undefined ? undefined : String(value);
  };
  const segment: Segment = {};

  const gender = oneOf(read("gender"), SEGMENT_GENDERS);
  if (gender) segment.gender = gender;
  const age = oneOf(read("age"), SEGMENT_AGES);
  if (age) segment.age_range = age;

  const days = Number(read("days"));
  if (Number.isInteger(days) && days >= 1 && days <= 365) segment.days = days;

  // Un atajo (boton) manda sobre el select de actividad.
  const activity = oneOf(read("preset"), SEGMENT_ACTIVITIES) ?? oneOf(read("activity"), SEGMENT_ACTIVITIES);
  if (activity) segment.activity = activity;

  const minReceipts = Number(read("min_receipts"));
  if (Number.isInteger(minReceipts) && minReceipts > 0 && minReceipts <= 1000) segment.min_receipts = minReceipts;

  const product = cleanText(read("product"), 60);
  if (product) segment.bought_product = product;
  const ruc = cleanText(read("ruc"), 40);
  if (ruc) segment.merchant_ruc = ruc;
  const payment = oneOf(read("payment"), SEGMENT_PAYMENTS);
  if (payment) segment.payment = payment;

  const minCashback = cleanText(read("min_cashback"), 12);
  if (minCashback) {
    const cents = parseDollarsToCents(minCashback);
    if (cents) segment.min_cashback = cents;
  }

  const dollars = (key: string) => {
    const text = cleanText(read(key), 14)?.replace(/[$,\s]/g, "");
    const value = Number(text);
    return text && Number.isFinite(value) && value > 0 && value < 10_000_000 ? Math.round(value * 100) / 100 : undefined;
  };
  const minSavings = dollars("min_savings");
  if (minSavings) segment.min_savings = minSavings;
  const minIncome = dollars("min_income");
  if (minIncome) segment.min_income = minIncome;
  const maxIncome = dollars("max_income");
  if (maxIncome) segment.max_income = maxIncome;
  return segment;
}

/// Segmento -> pares de campos del formulario (para hidden inputs y links).
export function segmentToFields(segment: Segment): Record<string, string> {
  const fields: Record<string, string> = {};
  if (segment.gender) fields.gender = segment.gender;
  if (segment.age_range) fields.age = segment.age_range;
  if (segment.days) fields.days = String(segment.days);
  if (segment.activity) fields.activity = segment.activity;
  if (segment.min_receipts) fields.min_receipts = String(segment.min_receipts);
  if (segment.bought_product) fields.product = segment.bought_product;
  if (segment.merchant_ruc) fields.ruc = segment.merchant_ruc;
  if (segment.payment) fields.payment = segment.payment;
  if (segment.min_cashback) fields.min_cashback = (segment.min_cashback / 100).toFixed(2);
  if (segment.min_savings) fields.min_savings = String(segment.min_savings);
  if (segment.min_income) fields.min_income = String(segment.min_income);
  if (segment.max_income) fields.max_income = String(segment.max_income);
  return fields;
}

/// Lee un segmento guardado (jsonb) de push_campaigns o bonus_grants.
export function segmentFromJson(raw: unknown): Segment {
  if (!raw || typeof raw !== "object") return {};
  const value = raw as Record<string, unknown>;
  return parseSegment((key) => {
    const map: Record<string, string> = { age: "age_range", product: "bought_product", ruc: "merchant_ruc" };
    const source = value[map[key] ?? key];
    if (key === "min_cashback") {
      const cents = Number(source);
      return Number.isFinite(cents) && cents > 0 ? (cents / 100).toFixed(2) : undefined;
    }
    return source === null || source === undefined ? undefined : String(source);
  });
}

const money = (value: number) => "$" + value.toLocaleString("en-US");

/// Descripcion corta para tablas e historial: ["Mujeres", "25-34 años", ...].
export function segmentLabels(segment: Segment): string[] {
  const labels: string[] = [];
  if (segment.gender) labels.push(SEGMENT_GENDER_LABELS[segment.gender]);
  if (segment.age_range) labels.push(`${segment.age_range} años`);
  if (segment.activity) labels.push(SEGMENT_PRESETS.find((p) => p.activity === segment.activity)?.label ?? segment.activity);
  if (segment.min_receipts) labels.push(`≥ ${segment.min_receipts} facturas`);
  if (segment.bought_product) labels.push(`Compró “${segment.bought_product}”`);
  if (segment.merchant_ruc) labels.push(`Compró en RUC ${segment.merchant_ruc}`);
  if (segment.payment) labels.push(SEGMENT_PAYMENT_LABELS[segment.payment]);
  if (segment.min_cashback) labels.push(`Cashback ≥ $${(segment.min_cashback / 100).toFixed(2)}`);
  if (segment.min_savings) labels.push("Ahorro ≥ " + money(segment.min_savings));
  if (segment.min_income && segment.max_income) {
    labels.push("Ingreso " + money(segment.min_income) + "–" + money(segment.max_income) + "/mes");
  } else if (segment.min_income) {
    labels.push("Ingreso ≥ " + money(segment.min_income) + "/mes");
  } else if (segment.max_income) {
    labels.push("Ingreso ≤ " + money(segment.max_income) + "/mes");
  }
  if (labels.length > 0) labels.push(`últimos ${segment.days ?? 30} días`);
  return labels;
}

export function segmentSummary(segment: Segment): string {
  const labels = segmentLabels(segment);
  return labels.length ? labels.join(" · ") : "Todos los que aceptaron ofertas";
}

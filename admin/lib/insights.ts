import "server-only";
import { supabaseAdmin } from "./supabase-admin";
import { num } from "./format";

// Estudio de mercado: wrapper de la RPC market_insights (migracion 0032).
// Todo es agregado y anonimo; los grupos con menos de p_min_users
// personas ya vienen suprimidos desde la base. Los numeros pueden llegar
// como number, string (numeric) o null: usar num() de lib/format.

type Num = number | string | null;

export type MarketInsights = {
  generated_at: string | null;
  days: Num;
  ruc: string | null;
  min_users: Num;
  filters: Record<string, string> | null;
  /// true cuando el segmento tiene menos de min_users personas: solo
  /// llegan summary.people y summary.consented_people.
  too_small: boolean;
  summary: {
    people: Num;
    receipts: Num;
    receipts_total: Num;
    avg_ticket: Num;
    median_ticket: Num;
    expenses_total: Num;
    avg_spend_per_person_month: Num;
    receipts_per_person_month: Num;
    points_issued: Num;
    redemptions: Num;
    avg_items_per_receipt: Num;
    consented_people: Num;
  };
  payment_methods: { method: string | null; receipts: Num; people: Num; share: Num; avg_ticket: Num }[];
  gender: { gender: string | null; people: Num; avg_spend: Num; avg_ticket: Num }[];
  age_ranges: { age_range: string | null; people: Num; avg_spend: Num; avg_ticket: Num }[];
  categories: { category: string | null; total: Num; purchases: Num; people: Num; avg_per_person: Num; share: Num }[];
  top_products: { product: string | null; times: Num; units: Num; total: Num; avg_price: Num; people: Num }[];
  top_merchants: {
    ruc: string | null;
    merchant: string | null;
    is_partner: boolean | null;
    visits: Num;
    people: Num;
    total: Num;
    avg_ticket: Num;
  }[];
  hours: { hour: Num; receipts: Num; avg_ticket: Num }[];
  weekdays: { dow: Num; receipts: Num; total: Num; avg_ticket: Num }[];
  heatmap: { dow: Num; hour: Num; receipts: Num }[];
  ticket_ranges: { sort: Num; range: string | null; receipts: Num }[];
  monthly: { month: string | null; receipts: Num; people: Num; total: Num; avg_ticket: Num }[];
  loyalty: { customers: Num; returning: Num; returning_share: Num; avg_visits: Num } | null;
  top_rewards: { reward: string | null; merchant: string | null; redemptions: Num; delivered: Num }[];
  month_days: { day: Num; receipts: Num; total: Num; avg_ticket: Num }[];
  dayparts: { sort: Num; daypart: string | null; receipts: Num; total: Num; avg_ticket: Num }[];
  frequency: { sort: Num; bucket: string | null; people: Num }[];
  also_shop_at: { ruc: string | null; merchant: string | null; people: Num; visits: Num; total: Num }[];
  payment_by_gender: { gender: string | null; method: string | null; receipts: Num; people: Num; avg_ticket: Num }[];
};

export const ALLOWED_DAYS = [30, 90, 365] as const;

export function parseDays(raw: string | undefined): number {
  const value = Number(raw);
  return (ALLOWED_DAYS as readonly number[]).includes(value) ? value : 90;
}

export function parseRuc(raw: string | undefined): string | null {
  const value = (raw ?? "").trim();
  if (!value || value.length > 40) return null;
  return value;
}

const EMPTY_SUMMARY: MarketInsights["summary"] = {
  people: 0,
  receipts: 0,
  receipts_total: 0,
  avg_ticket: null,
  median_ticket: null,
  expenses_total: 0,
  avg_spend_per_person_month: null,
  receipts_per_person_month: null,
  points_issued: 0,
  redemptions: 0,
  avg_items_per_receipt: null,
  consented_people: null,
};

function arr<T>(value: unknown): T[] {
  return Array.isArray(value) ? (value as T[]) : [];
}

/// Normaliza la respuesta para que todas las listas existan aunque la
/// base devuelva null o falte una llave.
function normalize(raw: unknown): MarketInsights {
  const data = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  return {
    generated_at: (data.generated_at as string) ?? null,
    days: (data.days as Num) ?? null,
    ruc: (data.ruc as string) ?? null,
    min_users: (data.min_users as Num) ?? 5,
    filters: data.filters && typeof data.filters === "object" ? (data.filters as Record<string, string>) : null,
    too_small: data.too_small === true,
    summary: { ...EMPTY_SUMMARY, ...((data.summary as object) ?? {}) },
    payment_methods: arr(data.payment_methods),
    gender: arr(data.gender),
    age_ranges: arr(data.age_ranges),
    categories: arr(data.categories),
    top_products: arr(data.top_products),
    top_merchants: arr(data.top_merchants),
    hours: arr(data.hours),
    weekdays: arr(data.weekdays),
    heatmap: arr(data.heatmap),
    ticket_ranges: arr(data.ticket_ranges),
    monthly: arr(data.monthly),
    loyalty: (data.loyalty as MarketInsights["loyalty"]) ?? null,
    top_rewards: arr(data.top_rewards),
    month_days: arr(data.month_days),
    dayparts: arr(data.dayparts),
    frequency: arr(data.frequency),
    also_shop_at: arr(data.also_shop_at),
    payment_by_gender: arr(data.payment_by_gender),
  };
}

// ---------------------------------------------------------------------------
// Filtros del segmento (genero, edad, medio de pago, producto, categoria)
// ---------------------------------------------------------------------------

export const GENDER_FILTERS = ["femenino", "masculino", "otro", "sin_dato"] as const;
export const AGE_FILTERS = ["18-24", "25-34", "35-44", "45-54", "55+", "Sin dato"] as const;
export const PAYMENT_FILTERS = ["tarjeta", "credito", "debito", "efectivo", "ach", "billetera"] as const;

export const PAYMENT_FILTER_LABELS: Record<(typeof PAYMENT_FILTERS)[number], string> = {
  tarjeta: "Tarjeta (crédito o débito)",
  credito: "Tarjeta de crédito",
  debito: "Tarjeta de débito",
  efectivo: "Efectivo",
  ach: "Transferencia ACH",
  billetera: "Billetera digital (Yappy, Nequi…)",
};

/// Categorias de gasto de la app (TransactionCategory.rawValue en iOS).
export const EXPENSE_CATEGORIES = [
  "Comida",
  "Supermercado",
  "Vivienda",
  "Servicios",
  "Transporte",
  "Compras",
  "Ropa",
  "Salir",
  "Entretenimiento",
  "Suscripciones",
  "Salud",
  "Educación",
  "Mascotas",
  "Regalos",
  "Viajes",
  "Ahorro",
  "Otro",
] as const;

export type InsightFilters = {
  gender: string | null;
  age_range: string | null;
  payment: string | null;
  product: string | null;
  category: string | null;
};

export const NO_FILTERS: InsightFilters = { gender: null, age_range: null, payment: null, product: null, category: null };

function oneOf(raw: string | null | undefined, allowed: readonly string[]): string | null {
  const value = (raw ?? "").trim();
  return allowed.includes(value) ? value : null;
}

function freeText(raw: string | null | undefined, maxLength: number): string | null {
  const value = (raw ?? "").trim().replace(/\s+/g, " ");
  if (!value) return null;
  return value.slice(0, maxLength);
}

/// Lee los filtros de los searchParams (pagina) o URLSearchParams (export).
export function parseInsightFilters(get: (key: string) => string | null | undefined): InsightFilters {
  return {
    gender: oneOf(get("gender"), GENDER_FILTERS),
    age_range: oneOf(get("age"), AGE_FILTERS),
    payment: oneOf(get("payment"), PAYMENT_FILTERS),
    product: freeText(get("product"), 80),
    category: freeText(get("category"), 60),
  };
}

export function hasFilters(filters: InsightFilters): boolean {
  return Object.values(filters).some((value) => value !== null);
}

/// Parametros de URL (sin "?") para repetir el mismo segmento en enlaces.
export function filtersQuery(filters: InsightFilters): string {
  const params = new URLSearchParams();
  if (filters.gender) params.set("gender", filters.gender);
  if (filters.age_range) params.set("age", filters.age_range);
  if (filters.payment) params.set("payment", filters.payment);
  if (filters.product) params.set("product", filters.product);
  if (filters.category) params.set("category", filters.category);
  return params.toString();
}

/// Etiquetas legibles de los filtros activos ("Género: Femenino", ...).
export function filterChips(filters: InsightFilters): { key: keyof InsightFilters; label: string }[] {
  const chips: { key: keyof InsightFilters; label: string }[] = [];
  if (filters.gender) chips.push({ key: "gender", label: `Género: ${GENDER_LABELS[filters.gender] ?? filters.gender}` });
  if (filters.age_range) chips.push({ key: "age_range", label: `Edad: ${filters.age_range}` });
  if (filters.payment) {
    const label = PAYMENT_FILTER_LABELS[filters.payment as (typeof PAYMENT_FILTERS)[number]] ?? filters.payment;
    chips.push({ key: "payment", label: `Pago: ${label}` });
  }
  if (filters.product) chips.push({ key: "product", label: `Producto: “${filters.product}”` });
  if (filters.category) chips.push({ key: "category", label: `Categoría: ${filters.category}` });
  return chips;
}

export async function fetchMarketInsights(
  days: number,
  ruc: string | null,
  filters: InsightFilters = NO_FILTERS
): Promise<{ data?: MarketInsights; error?: string }> {
  // Los filtros vacios se omiten: la RPC los toma como null (sin filtro).
  const args: Record<string, string | number | null> = { p_days: days, p_ruc: ruc, p_min_users: 5 };
  if (filters.gender) args.p_gender = filters.gender;
  if (filters.age_range) args.p_age_range = filters.age_range;
  if (filters.payment) args.p_payment = filters.payment;
  if (filters.product) args.p_product = filters.product;
  if (filters.category) args.p_category = filters.category;
  const { data, error } = await supabaseAdmin().rpc("market_insights", args);
  if (error) return { error: error.message };
  return { data: normalize(data) };
}

export const GENDER_LABELS: Record<string, string> = {
  femenino: "Femenino",
  masculino: "Masculino",
  otro: "Otro",
  prefiero_no_decir: "Prefiere no decir",
  sin_dato: "Sin dato",
};

export const WEEKDAY_LABELS = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"];

export function weekdayLabel(dow: unknown): string {
  const index = Number(dow) - 1;
  return WEEKDAY_LABELS[index] ?? "—";
}

export function paymentMethodLabel(method: string | null): string {
  if (!method) return "Sin dato";
  const clean = method.replace(/_/g, " ").trim();
  return clean.charAt(0).toUpperCase() + clean.slice(1);
}

// ---------------------------------------------------------------------------
// CSV por seccion (para /insights/export)
// ---------------------------------------------------------------------------

type Column = { key: string; header: string; map?: (value: unknown, row: Record<string, unknown>) => unknown };

export const CSV_SECTIONS: Record<string, { title: string; columns: Column[]; rows: (data: MarketInsights) => unknown[] }> = {
  summary: {
    title: "Resumen",
    columns: [
      { key: "metric", header: "Indicador" },
      { key: "value", header: "Valor" },
    ],
    rows: (data) => {
      const s = data.summary;
      return [
        { metric: "Personas", value: s.people },
        { metric: "Facturas", value: s.receipts },
        { metric: "Total facturado (USD)", value: s.receipts_total },
        { metric: "Ticket promedio (USD)", value: s.avg_ticket },
        { metric: "Ticket mediano (USD)", value: s.median_ticket },
        { metric: "Gastos registrados (USD)", value: s.expenses_total },
        { metric: "Gasto promedio por persona al mes (USD)", value: s.avg_spend_per_person_month },
        { metric: "Compras por persona al mes", value: s.receipts_per_person_month },
        { metric: "Cashback emitido (USD)", value: s.points_issued === null ? null : num(s.points_issued) / 100 },
        { metric: "Canjes", value: s.redemptions },
        { metric: "Productos promedio por factura", value: s.avg_items_per_receipt },
        { metric: "Personas que aceptaron el estudio", value: s.consented_people },
      ];
    },
  },
  payment_methods: {
    title: "Formas de pago",
    columns: [
      { key: "method", header: "Forma de pago", map: (v) => paymentMethodLabel(v as string | null) },
      { key: "receipts", header: "Facturas" },
      { key: "people", header: "Personas" },
      { key: "share", header: "Porcentaje" },
      { key: "avg_ticket", header: "Ticket promedio (USD)" },
    ],
    rows: (data) => data.payment_methods,
  },
  gender: {
    title: "Género",
    columns: [
      { key: "gender", header: "Género", map: (v) => GENDER_LABELS[String(v)] ?? v },
      { key: "people", header: "Personas" },
      { key: "avg_spend", header: "Gasto promedio (USD)" },
      { key: "avg_ticket", header: "Ticket promedio (USD)" },
    ],
    rows: (data) => data.gender,
  },
  age_ranges: {
    title: "Edades",
    columns: [
      { key: "age_range", header: "Rango de edad" },
      { key: "people", header: "Personas" },
      { key: "avg_spend", header: "Gasto promedio (USD)" },
      { key: "avg_ticket", header: "Ticket promedio (USD)" },
    ],
    rows: (data) => data.age_ranges,
  },
  categories: {
    title: "Categorías de gasto",
    columns: [
      { key: "category", header: "Categoría" },
      { key: "total", header: "Total (USD)" },
      { key: "purchases", header: "Compras" },
      { key: "people", header: "Personas" },
      { key: "avg_per_person", header: "Promedio por persona (USD)" },
      { key: "share", header: "Porcentaje del gasto" },
    ],
    rows: (data) => data.categories,
  },
  top_products: {
    title: "Productos más comprados",
    columns: [
      { key: "product", header: "Producto" },
      { key: "times", header: "Veces comprado" },
      { key: "units", header: "Unidades" },
      { key: "total", header: "Total (USD)" },
      { key: "avg_price", header: "Precio promedio (USD)" },
      { key: "people", header: "Personas" },
    ],
    rows: (data) => data.top_products,
  },
  top_merchants: {
    title: "Comercios más visitados",
    columns: [
      { key: "merchant", header: "Comercio" },
      { key: "ruc", header: "RUC" },
      { key: "is_partner", header: "Aliado MonAvi", map: (v) => (v ? "Sí" : "No") },
      { key: "visits", header: "Visitas" },
      { key: "people", header: "Personas" },
      { key: "total", header: "Total (USD)" },
      { key: "avg_ticket", header: "Ticket promedio (USD)" },
    ],
    rows: (data) => data.top_merchants,
  },
  hours: {
    title: "Compras por hora",
    columns: [
      { key: "hour", header: "Hora" },
      { key: "receipts", header: "Facturas" },
      { key: "avg_ticket", header: "Ticket promedio (USD)" },
    ],
    rows: (data) => data.hours,
  },
  weekdays: {
    title: "Compras por día de la semana",
    columns: [
      { key: "dow", header: "Día", map: (v) => weekdayLabel(v) },
      { key: "receipts", header: "Facturas" },
      { key: "total", header: "Total (USD)" },
      { key: "avg_ticket", header: "Ticket promedio (USD)" },
    ],
    rows: (data) => data.weekdays,
  },
  heatmap: {
    title: "Mapa de calor día x hora",
    columns: [
      { key: "dow", header: "Día", map: (v) => weekdayLabel(v) },
      { key: "hour", header: "Hora" },
      { key: "receipts", header: "Facturas" },
    ],
    rows: (data) => data.heatmap,
  },
  ticket_ranges: {
    title: "Rangos de ticket",
    columns: [
      { key: "range", header: "Rango" },
      { key: "receipts", header: "Facturas" },
    ],
    rows: (data) => data.ticket_ranges,
  },
  monthly: {
    title: "Tendencia mensual",
    columns: [
      { key: "month", header: "Mes" },
      { key: "receipts", header: "Facturas" },
      { key: "people", header: "Personas" },
      { key: "total", header: "Total (USD)" },
      { key: "avg_ticket", header: "Ticket promedio (USD)" },
    ],
    rows: (data) => data.monthly,
  },
  loyalty: {
    title: "Recurrencia",
    columns: [
      { key: "customers", header: "Clientes" },
      { key: "returning", header: "Clientes que vuelven" },
      { key: "returning_share", header: "Porcentaje que vuelve" },
      { key: "avg_visits", header: "Visitas promedio" },
    ],
    rows: (data) => (data.loyalty ? [data.loyalty] : []),
  },
  top_rewards: {
    title: "Productos canjeados",
    columns: [
      { key: "reward", header: "Producto" },
      { key: "merchant", header: "Comercio" },
      { key: "redemptions", header: "Canjes" },
      { key: "delivered", header: "Entregados" },
    ],
    rows: (data) => data.top_rewards,
  },
  month_days: {
    title: "Compras por día del mes",
    columns: [
      { key: "day", header: "Día del mes" },
      { key: "receipts", header: "Facturas" },
      { key: "total", header: "Total (USD)" },
      { key: "avg_ticket", header: "Ticket promedio (USD)" },
    ],
    rows: (data) => data.month_days,
  },
  dayparts: {
    title: "Momento del día",
    columns: [
      { key: "daypart", header: "Momento del día" },
      { key: "receipts", header: "Facturas" },
      { key: "total", header: "Total (USD)" },
      { key: "avg_ticket", header: "Ticket promedio (USD)" },
    ],
    rows: (data) => data.dayparts,
  },
  frequency: {
    title: "Frecuencia de compra",
    columns: [
      { key: "bucket", header: "Compras en el periodo" },
      { key: "people", header: "Personas" },
    ],
    rows: (data) => data.frequency,
  },
  also_shop_at: {
    title: "Dónde más compran también sus clientes",
    columns: [
      { key: "merchant", header: "Comercio" },
      { key: "ruc", header: "RUC" },
      { key: "people", header: "Personas" },
      { key: "visits", header: "Visitas" },
      { key: "total", header: "Total (USD)" },
    ],
    rows: (data) => data.also_shop_at,
  },
  payment_by_gender: {
    title: "Medio de pago por género",
    columns: [
      { key: "gender", header: "Género", map: (v) => GENDER_LABELS[String(v)] ?? v },
      { key: "method", header: "Medio de pago" },
      { key: "receipts", header: "Facturas" },
      { key: "people", header: "Personas" },
      { key: "avg_ticket", header: "Ticket promedio (USD)" },
    ],
    rows: (data) => data.payment_by_gender,
  },
};

function csvCell(value: unknown): string {
  if (value === null || value === undefined) return "";
  const textValue = String(value);
  // Evita inyeccion de formulas al abrir el CSV en Excel/Sheets.
  const safe = /^[=+\-@\t\r]/.test(textValue) && !/^-?\d/.test(textValue) ? `'${textValue}` : textValue;
  return /[",\n\r]/.test(safe) ? `"${safe.replace(/"/g, '""')}"` : safe;
}

export function sectionToCsv(section: string, data: MarketInsights): string | null {
  const definition = CSV_SECTIONS[section];
  if (!definition) return null;
  const lines = [definition.columns.map((column) => csvCell(column.header)).join(",")];
  for (const raw of definition.rows(data)) {
    const row = (raw ?? {}) as Record<string, unknown>;
    lines.push(
      definition.columns
        .map((column) => csvCell(column.map ? column.map(row[column.key], row) : row[column.key]))
        .join(",")
    );
  }
  return `﻿${lines.join("\r\n")}\r\n`;
}

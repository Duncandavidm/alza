import "server-only";
import { supabaseAdmin } from "./supabase-admin";

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
  };
  payment_methods: { method: string | null; receipts: Num; people: Num; share: Num }[];
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
  };
}

export async function fetchMarketInsights(
  days: number,
  ruc: string | null
): Promise<{ data?: MarketInsights; error?: string }> {
  const { data, error } = await supabaseAdmin().rpc("market_insights", {
    p_days: days,
    p_ruc: ruc,
    p_min_users: 5,
  });
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
        { metric: "Puntos emitidos", value: s.points_issued },
        { metric: "Canjes", value: s.redemptions },
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

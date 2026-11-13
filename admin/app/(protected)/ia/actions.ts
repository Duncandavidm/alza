"use server";

import { requireAdminSession } from "@/lib/admin-session";

import { revalidatePath } from "next/cache";
import { supabaseAdmin } from "@/lib/supabase-admin";
import type { ActionState } from "@/components/ActionForm";
import { AI_FUNCTIONS } from "./functions";

type Quota = { limit?: number; period?: string };

/// Guarda el tope diario (app_config.ai_daily_budget_usd) y el limite de
/// cada cuota (app_config.ai_quotas). El periodo (dia o mes) de cada
/// cuota se conserva tal como esta.
export async function updateAiSettings(_prev: ActionState, formData: FormData): Promise<ActionState> {
  await requireAdminSession();
  const budgetRaw = (formData.get("budget_usd")?.toString() ?? "").trim().replace(/^\$/, "").replace(",", ".");
  const budget = Number(budgetRaw);
  if (!budgetRaw || !Number.isFinite(budget) || budget < 0.5 || budget > 1000) {
    return { error: "El tope diario debe estar entre $0.50 y $1,000.00." };
  }

  const limits: Record<string, number> = {};
  for (const fn of AI_FUNCTIONS) {
    const raw = (formData.get(`limit_${fn.key}`)?.toString() ?? "").trim();
    const value = Number(raw);
    if (!/^\d+$/.test(raw) || !Number.isInteger(value) || value < 0 || value > 10000) {
      return { error: `El límite de “${fn.label}” debe ser un número entero entre 0 y 10,000.` };
    }
    limits[fn.key] = value;
  }

  const supabase = supabaseAdmin();
  const { data: current, error: readError } = await supabase
    .from("app_config")
    .select("value")
    .eq("key", "ai_quotas")
    .maybeSingle<{ value: Record<string, Quota> | null }>();
  if (readError) return { error: `No se pudieron leer las cuotas: ${readError.message}` };

  const quotas: Record<string, Quota> = { ...(current?.value ?? {}) };
  for (const fn of AI_FUNCTIONS) {
    const existing = quotas[fn.key] ?? {};
    quotas[fn.key] = { ...existing, limit: limits[fn.key], period: existing.period ?? fn.defaultPeriod };
  }

  const { error } = await supabase.from("app_config").upsert(
    [
      { key: "ai_daily_budget_usd", value: Math.round(budget * 100) / 100 },
      { key: "ai_quotas", value: quotas },
    ],
    { onConflict: "key" }
  );
  if (error) return { error: `No se pudo guardar: ${error.message}` };

  revalidatePath("/ia");
  return { message: "Configuración guardada." };
}

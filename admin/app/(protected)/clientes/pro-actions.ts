"use server";

import { revalidatePath } from "next/cache";
import { requireAdminSession } from "@/lib/admin-session";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { text } from "@/lib/validation";
import type { ActionState } from "@/components/ActionForm";

function price(formData: FormData, key: string, max: number): number | null {
  const raw = text(formData, key, 12).replace("$", "").replace(",", ".").trim();
  const value = Number(raw);
  return raw !== "" && Number.isFinite(value) && value >= 0 && value <= max ? Math.round(value * 100) / 100 : null;
}

/// Precios de MonAvi Pro y comision de Apple, solo para estimar ingresos
/// en el panel (los precios reales se cambian en App Store Connect).
export async function updateProPrices(_prev: ActionState, formData: FormData): Promise<ActionState> {
  await requireAdminSession();
  const monthly = price(formData, "monthly", 500);
  const annual = price(formData, "annual", 5000);
  const commission = price(formData, "commission", 100);
  if (monthly === null) return { error: "El precio mensual debe ser un monto, por ejemplo 7.99." };
  if (annual === null) return { error: "El precio anual debe ser un monto, por ejemplo 74.99." };
  if (commission === null) return { error: "La comisión de Apple debe ser un porcentaje entre 0 y 100 (15 o 30)." };

  const now = new Date().toISOString();
  const { error } = await supabaseAdmin()
    .from("app_config")
    .upsert(
      [
        { key: "pro_price_monthly_usd", value: monthly, updated_at: now },
        { key: "pro_price_annual_usd", value: annual, updated_at: now },
        { key: "apple_commission_pct", value: commission, updated_at: now },
      ],
      { onConflict: "key" }
    );
  if (error) return { error: error.message };
  revalidatePath("/clientes");
  revalidatePath("/");
  return { message: "Listo: el ingreso estimado ya usa estos precios." };
}

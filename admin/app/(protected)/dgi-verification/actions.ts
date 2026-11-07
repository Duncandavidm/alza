"use server";

import { revalidatePath } from "next/cache";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { callReconcileFunction } from "@/lib/edge-functions";

export async function setDgiVerificationEnabled(enabled: boolean) {
  const supabase = supabaseAdmin();
  const { error } = await supabase
    .from("app_config")
    .update({ value: enabled })
    .eq("key", "dgi_verification_enabled");
  if (error) throw new Error(error.message);

  revalidatePath("/dgi-verification");
}

export async function updateDgiRules(formData: FormData) {
  const pointsPerDollar = Number(formData.get("points_per_dollar"));
  const dailyCap = Number(formData.get("daily_cap_points_per_user"));
  const expireAfterDays = Number(formData.get("expire_after_days"));

  if (!Number.isFinite(pointsPerDollar) || pointsPerDollar < 0) {
    throw new Error("El cashback por factura (puntos por dólar) no es válido.");
  }
  if (!Number.isFinite(dailyCap) || dailyCap < 0) {
    throw new Error("Tope diario inválido.");
  }
  if (!Number.isFinite(expireAfterDays) || expireAfterDays < 1) {
    throw new Error("Días para expirar inválido.");
  }

  const supabase = supabaseAdmin();
  const { error: rulesError } = await supabase
    .from("points_rules")
    .upsert(
      [
        { source: "factura", key: "points_per_dollar", value: pointsPerDollar },
        { source: "factura", key: "daily_cap_points_per_user", value: dailyCap },
      ],
      { onConflict: "source,key" }
    );
  if (rulesError) throw new Error(rulesError.message);

  const { error: configError } = await supabase
    .from("app_config")
    .update({ value: expireAfterDays })
    .eq("key", "dgi_verification_expire_after_days");
  if (configError) throw new Error(configError.message);

  revalidatePath("/dgi-verification");
}

export async function runDgiVerificationNow(): Promise<{ error?: string; summary?: string }> {
  try {
    const result = await callReconcileFunction("verify-dgi-receipt", {});
    if (!result.ok) {
      return { error: `La funcion respondio ${result.status}: ${JSON.stringify(result.data)}` };
    }
    revalidatePath("/dgi-verification");
    return { summary: JSON.stringify(result.data) };
  } catch (error) {
    return { error: error instanceof Error ? error.message : String(error) };
  }
}

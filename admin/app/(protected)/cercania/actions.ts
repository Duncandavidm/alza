"use server";

import { revalidatePath } from "next/cache";
import { requireAdminSession } from "@/lib/admin-session";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { text } from "@/lib/validation";
import { resolveMapsLocation } from "@/lib/geo";
import type { ActionState } from "@/components/ActionForm";

function intField(formData: FormData, key: string, min: number, max: number): number | null {
  const value = Number(text(formData, key, 6));
  return Number.isInteger(value) && value >= min && value <= max ? value : null;
}

/// Ajustes generales de los avisos por cercania (app_config). La app los
/// leera al programar los avisos, sin necesidad de actualizarla para
/// cambiarlos.
export async function updateProximitySettings(_prev: ActionState, formData: FormData): Promise<ActionState> {
  await requireAdminSession();
  const radius = intField(formData, "radius", 100, 2000);
  const cooldown = intField(formData, "cooldown", 1, 60);
  const dailyMax = intField(formData, "daily_max", 1, 10);
  const quietStart = intField(formData, "quiet_start", 0, 23);
  const quietEnd = intField(formData, "quiet_end", 0, 23);
  if (radius === null) return { error: "El radio debe ser entre 100 y 2000 metros." };
  if (cooldown === null) return { error: "Los días entre avisos del mismo comercio deben ser entre 1 y 60." };
  if (dailyMax === null) return { error: "El máximo de avisos por día debe ser entre 1 y 10." };
  if (quietStart === null || quietEnd === null) return { error: "Las horas de silencio van de 0 a 23." };
  const enabled = formData.get("enabled") === "on";

  const now = new Date().toISOString();
  const { error } = await supabaseAdmin()
    .from("app_config")
    .upsert(
      [
        { key: "proximity_alerts_enabled", value: enabled, updated_at: now },
        { key: "proximity_radius_m", value: radius, updated_at: now },
        { key: "proximity_cooldown_days", value: cooldown, updated_at: now },
        { key: "proximity_daily_max", value: dailyMax, updated_at: now },
        { key: "proximity_quiet_start_hour", value: quietStart, updated_at: now },
        { key: "proximity_quiet_end_hour", value: quietEnd, updated_at: now },
        { key: "proximity_only_with_benefit", value: true, updated_at: now },
      ],
      { onConflict: "key" }
    );
  if (error) return { error: error.message };
  revalidatePath("/cercania");
  return { message: "Ajustes guardados." };
}

/// Saca la ubicacion de todos los locales que tienen enlace de Maps pero
/// todavia no tienen coordenadas.
export async function locateAllMissing(_prev: ActionState): Promise<ActionState> {
  await requireAdminSession();
  const supabase = supabaseAdmin();
  const [{ data: merchants, error }, { data: branches }] = await Promise.all([
    supabase.from("partner_merchants").select("id, maps_url").is("latitude", null).not("maps_url", "is", null).limit(200),
    supabase.from("merchant_branches").select("id, maps_url").is("latitude", null).not("maps_url", "is", null).limit(200),
  ]);
  if (error) return { error: `Falta aplicar la migración 0080 en Supabase (${error.message}).` };

  let found = 0;
  let missed = 0;
  const jobs: { table: "partner_merchants" | "merchant_branches"; id: string; url: string }[] = [
    ...((merchants ?? []) as { id: string; maps_url: string }[]).map((m) => ({ table: "partner_merchants" as const, id: m.id, url: m.maps_url })),
    ...((branches ?? []) as { id: string; maps_url: string }[]).map((b) => ({ table: "merchant_branches" as const, id: b.id, url: b.maps_url })),
  ];
  for (const job of jobs) {
    const coords = await resolveMapsLocation(job.url);
    if (coords) {
      const { error: updateError } = await supabase.from(job.table).update(coords).eq("id", job.id);
      if (updateError) missed += 1;
      else found += 1;
    } else {
      missed += 1;
    }
  }
  revalidatePath("/cercania");
  if (jobs.length === 0) return { message: "No hay locales con enlace de Maps pendientes de ubicar." };
  return {
    message: `Ubicados ${found} de ${jobs.length}.${missed > 0 ? ` A ${missed} no se les pudo sacar del enlace: ponles las coordenadas a mano en su ficha.` : ""}`,
  };
}

"use server";

import { revalidatePath } from "next/cache";
import { requireAdminSession } from "@/lib/admin-session";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { parseDollarsToCents } from "@/lib/format";
import { text } from "@/lib/validation";
import type { ActionState } from "@/components/ActionForm";

/// "0" apaga ese premio; si no, un monto en US$ hasta $50.
function centsField(formData: FormData, key: string): number | null {
  const raw = text(formData, key, 12).trim();
  if (/^\$?\s*0+([.,]0{1,2})?$/.test(raw)) return 0;
  const cents = parseDollarsToCents(raw);
  return cents !== null && cents <= 5_000 ? cents : null;
}

/// Montos de cashback por invitar y tope mensual (app_config). La app los
/// lee del servidor al abrir "Invita amigos", sin actualizarla.
export async function updateReferralRewards(_prev: ActionState, formData: FormData): Promise<ActionState> {
  await requireAdminSession();
  const referrer = centsField(formData, "referrer");
  const referee = centsField(formData, "referee");
  if (referrer === null) return { error: "El cashback de quien invita debe ser un monto entre $0 y $50 (por ejemplo 2 o 1.50)." };
  if (referee === null) return { error: "El cashback del amigo invitado debe ser un monto entre $0 y $50." };
  const capRaw = Number(text(formData, "cap", 6));
  if (!Number.isInteger(capRaw) || capRaw < 1 || capRaw > 100) {
    return { error: "El tope de amigos premiados por mes debe ser un número entre 1 y 100." };
  }

  const now = new Date().toISOString();
  const { error } = await supabaseAdmin()
    .from("app_config")
    .upsert(
      [
        { key: "referral_cashback_referrer_cents", value: referrer, updated_at: now },
        { key: "referral_cashback_referee_cents", value: referee, updated_at: now },
        { key: "referral_monthly_cap", value: capRaw, updated_at: now },
      ],
      { onConflict: "key" }
    );
  if (error) return { error: error.message };
  revalidatePath("/referidos");
  return { message: "Listo: la app ya muestra los montos nuevos y se pagan desde el próximo amigo que cumpla." };
}

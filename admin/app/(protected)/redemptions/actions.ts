"use server";

import { requireAdminSession, assertUuid } from "@/lib/admin-session";

import { revalidatePath } from "next/cache";
import { supabaseAdmin } from "@/lib/supabase-admin";
import type { ActionState } from "@/components/ActionForm";

/// El cliente mostró su código en caja y el comercio entregó el producto,
/// pero se marca desde el panel (delivered_via = 'panel'); lo normal es
/// que el comercio lo valide en /canjear (delivered_via = 'comercio').
export async function markRedemptionDelivered(redemptionId: string): Promise<ActionState> {
  await requireAdminSession();
  assertUuid(redemptionId);
  const { data, error } = await supabaseAdmin()
    .from("reward_redemptions")
    .update({ status: "entregado", delivered_at: new Date().toISOString(), delivered_via: "panel" })
    .eq("id", redemptionId)
    .eq("status", "emitido")
    .gt("expires_at", new Date().toISOString())
    .select("id");
  if (error) return { error: error.message };
  if (!data || data.length === 0) {
    return { error: "No se pudo marcar: el canje ya no está emitido o ya venció." };
  }

  revalidatePath("/redemptions");
  return { message: "Marcado como entregado." };
}

/// Cancela un canje emitido y devuelve el cashback o los puntos al cliente
/// (rpc release_redemption, solo service role).
export async function cancelRedemption(redemptionId: string): Promise<ActionState> {
  await requireAdminSession();
  assertUuid(redemptionId);
  const { data, error } = await supabaseAdmin().rpc("release_redemption", {
    p_redemption_id: redemptionId,
    p_status: "cancelado",
  });
  if (error) return { error: error.message };

  const row = (Array.isArray(data) ? data[0] : data) as { status?: string } | null;
  revalidatePath("/redemptions");
  if (row?.status !== "cancelado") {
    return { error: `No se canceló: el canje ya estaba “${row?.status ?? "desconocido"}”.` };
  }
  return { message: "Cancelado; el valor se devolvió al cliente." };
}

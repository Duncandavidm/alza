"use server";

import { requireAdminSession } from "@/lib/admin-session";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { callSendPush, describeBonusResult } from "@/lib/edge";
import { parseBonusInput } from "@/lib/bonuses";
import { parseUuid } from "@/lib/push";
import { parseSegment } from "@/lib/segments";
import type { ActionState } from "@/components/ActionForm";

/// Guarda el bono (bonus_grants) y lo entrega con la Edge Function
/// send-push ({ bonus_id }): grant_bonus() lo da a cada persona del
/// segmento una sola vez y, si notify, les avisa por push.
export async function grantBonus(_prev: ActionState, formData: FormData): Promise<ActionState> {
  await requireAdminSession();
  const parsed = parseBonusInput((key) => formData.get(key)?.toString());
  if (!parsed.input) return { error: parsed.error ?? "Datos inválidos." };
  const segment = parseSegment((key) => formData.get(key)?.toString());
  const supabase = supabaseAdmin();

  if (parsed.input.reward_item_id) {
    const { data: item } = await supabase
      .from("reward_items")
      .select("id, status")
      .eq("id", parsed.input.reward_item_id)
      .maybeSingle<{ id: string; status: string }>();
    if (!item) return { error: "No se encontró el producto." };
    if (item.status !== "active") return { error: "Ese producto está pausado: actívalo en su comercio o elige otro." };
  }

  const { data: created, error } = await supabase
    .from("bonus_grants")
    .insert({ ...parsed.input, segment, status: "draft" })
    .select("id")
    .single<{ id: string }>();
  if (error || !created) return { error: `No se pudo guardar el bono: ${error?.message ?? "error desconocido"}` };

  const sent = await callSendPush({ bonus_id: created.id });
  revalidatePath("/bonos");
  if (!sent.ok) {
    return { error: `Se guardó, pero no se pudo entregar: ${sent.error}. Puedes reintentar desde el historial.` };
  }
  redirect(`/bonos?done=${created.id}&msg=${encodeURIComponent(describeBonusResult(sent.result, parsed.input.notify))}`);
}

/// Reintenta la entrega de un bono que quedo en borrador (grant_bonus es
/// idempotente por persona: nadie lo recibe dos veces).
export async function retryBonus(bonusId: string) {
  await requireAdminSession();
  const id = parseUuid(bonusId);
  if (!id) throw new Error("Bono inválido.");
  const { data: bonus } = await supabaseAdmin()
    .from("bonus_grants")
    .select("notify")
    .eq("id", id)
    .maybeSingle<{ notify: boolean }>();
  const sent = await callSendPush({ bonus_id: id });
  revalidatePath("/bonos");
  const msg = sent.ok ? describeBonusResult(sent.result, Boolean(bonus?.notify)) : `No se pudo entregar: ${sent.error}`;
  redirect(`/bonos?done=${id}&msg=${encodeURIComponent(msg)}`);
}

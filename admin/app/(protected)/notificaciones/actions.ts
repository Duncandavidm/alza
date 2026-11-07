"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { callSendPush, describePushResult } from "@/lib/edge";
import { PUSH_BODY_MAX, PUSH_TITLE_MAX, cleanLine, parseUuid, toPushScreen } from "@/lib/push";
import { parseSegment } from "@/lib/segments";
import type { ActionState } from "@/components/ActionForm";

/// Guarda la notificacion (push_campaigns) y la envia con la Edge
/// Function send-push. La Edge Function vuelve a calcular el segmento al
/// enviar y solo incluye a quienes aceptaron 'ofertas'.
export async function sendPushCampaign(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const title = cleanLine(formData.get("title"), PUSH_TITLE_MAX);
  const body = cleanLine(formData.get("body"), PUSH_BODY_MAX);
  const screen = toPushScreen(formData.get("screen"));
  const brandCampaignId = parseUuid(formData.get("brand_campaign_id"));
  const segment = parseSegment((key) => formData.get(key)?.toString());

  if (!title) return { error: "Falta el título." };
  if (!body) return { error: "Falta el mensaje." };

  const { data: created, error } = await supabaseAdmin()
    .from("push_campaigns")
    .insert({ title, body, screen, segment, brand_campaign_id: brandCampaignId, status: "draft" })
    .select("id")
    .single<{ id: string }>();
  if (error || !created) return { error: `No se pudo guardar la notificación: ${error?.message ?? "error desconocido"}` };

  const sent = await callSendPush({ push_campaign_id: created.id });
  revalidatePath("/notificaciones");
  if (!sent.ok) {
    return {
      error: `Se guardó, pero no se pudo enviar: ${sent.error}. Puedes reintentar desde el historial.`,
    };
  }
  redirect(`/notificaciones?done=${created.id}&msg=${encodeURIComponent(describePushResult(sent.result))}`);
}

/// Reintenta una notificacion que quedo sin enviar o fallo.
export async function retryPushCampaign(campaignId: string) {
  const id = parseUuid(campaignId);
  if (!id) throw new Error("Notificación inválida.");
  // send-push rechaza las que ya estan 'sending'/'sent'; una fallida se
  // vuelve a dejar en borrador para poder reenviarla.
  await supabaseAdmin().from("push_campaigns").update({ status: "draft", error: null }).eq("id", id).eq("status", "failed");
  const sent = await callSendPush({ push_campaign_id: id });
  revalidatePath("/notificaciones");
  const msg = sent.ok ? describePushResult(sent.result) : `No se pudo enviar: ${sent.error}`;
  redirect(`/notificaciones?done=${id}&msg=${encodeURIComponent(msg)}`);
}

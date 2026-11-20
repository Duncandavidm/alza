// Edge Function: send-push
//
// Lo llama el panel:
//   { push_campaign_id }  envia una notificacion segmentada (push_campaigns)
//   { bonus_id }          entrega un bono/regalo (grant_bonus) y, si el bono
//                         lo pide, avisa por push a quienes lo recibieron
//
// Solo llega a personas con el consentimiento 'ofertas' (lo filtra
// segment_user_ids). Exige x-admin-secret; verify_jwt: false.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendPushToUsers } from "./apns.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ADMIN_JOB_SECRET = Deno.env.get("ADMIN_JOB_SECRET")!;

const CORS_HEADERS = {
  "Access-Control-Allow-Headers": "x-admin-secret, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

function formatCents(cents: number): string {
  return "$" + (cents / 100).toFixed(2);
}

function errorText(error: unknown): string {
  return String((error as { message?: string })?.message ?? error);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.headers.get("x-admin-secret") !== ADMIN_JOB_SECRET) {
    return jsonResponse({ error: "No autorizado" }, 401);
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  let body: { push_campaign_id?: string; bonus_id?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "JSON invalido" }, 400);
  }

  try {
    if (body.push_campaign_id) {
      const { data: campaign, error } = await supabase
        .from("push_campaigns").select("*").eq("id", body.push_campaign_id).single();
      if (error || !campaign) return jsonResponse({ error: "Notificacion no encontrada" }, 404);
      if (campaign.status === "sent" || campaign.status === "sending") {
        return jsonResponse({ error: "Esta notificacion ya se envio" }, 409);
      }
      await supabase.from("push_campaigns").update({ status: "sending" }).eq("id", campaign.id);

      const { data: users, error: segmentError } = await supabase.rpc("segment_user_ids", { p_segment: campaign.segment });
      if (segmentError) throw segmentError;
      const userIds = ((users ?? []) as { user_id: string }[]).map((row) => row.user_id);

      const result = await sendPushToUsers(supabase, userIds, {
        title: campaign.title,
        body: campaign.body,
        data: { screen: campaign.screen, push_campaign_id: campaign.id },
        threadId: "monavi-ofertas",
      });
      await supabase.from("push_campaigns").update({
        status: "sent",
        target_count: userIds.length,
        sent_count: result.people,
        failed_count: result.failed,
        error: result.skipped ?? null,
        sent_at: new Date().toISOString(),
      }).eq("id", campaign.id);
      return jsonResponse({ ok: true, target: userIds.length, ...result });
    }

    if (body.bonus_id) {
      const { data: bonus, error } = await supabase
        .from("bonus_grants")
        .select("*, reward_items(name, partner_merchants(name))")
        .eq("id", body.bonus_id)
        .single();
      if (error || !bonus) return jsonResponse({ error: "Bono no encontrado" }, 404);

      const startedAt = new Date().toISOString();
      const { data: granted, error: grantError } = await supabase.rpc("grant_bonus", { p_bonus_id: bonus.id });
      if (grantError) throw grantError;

      let push: { sent: number; failed: number; people: number; skipped?: string } = { sent: 0, failed: 0, people: 0 };
      if (bonus.notify && (granted ?? 0) > 0) {
        // Solo a quienes lo recibieron en esta entrega.
        const { data: recipients } = await supabase
          .from("bonus_recipients").select("user_id").eq("bonus_id", bonus.id).gte("created_at", startedAt);
        const userIds = ((recipients ?? []) as { user_id: string }[]).map((row) => row.user_id);

        let title: string;
        let text: string;
        let screen: string;
        if (bonus.kind === "cashback") {
          title = "🎁 ¡Te regalamos " + formatCents(bonus.amount) + " de cashback!";
          text = bonus.message || "Ya está en tu saldo. Úsalo en los comercios aliados de MonAvi.";
          screen = "rewards";
        } else if (bonus.kind === "puntos") {
          title = "🎁 ¡Te regalamos " + bonus.amount + " puntos!";
          text = bonus.message || "Ya están en tu saldo. Canjéalos en los comercios aliados.";
          screen = "rewards";
        } else {
          const item = bonus.reward_items as { name?: string; partner_merchants?: { name?: string } } | null;
          title = "🎁 ¡Tienes " + (item?.name ?? "un regalo") + " gratis!";
          text = bonus.message ||
            "Te espera en " + (item?.partner_merchants?.name ?? "un comercio aliado") + ". Muestra tu código en caja.";
          screen = "redemptions";
        }
        push = await sendPushToUsers(supabase, userIds, {
          title,
          body: text,
          data: { screen, bonus_id: bonus.id },
          threadId: "monavi-regalos",
        });
      }
      return jsonResponse({ ok: true, granted: granted ?? 0, push });
    }

    return jsonResponse({ error: "Falta push_campaign_id o bonus_id" }, 400);
  } catch (error) {
    console.error("send-push fallo", error);
    if (body.push_campaign_id) {
      await supabase.from("push_campaigns").update({ status: "failed", error: errorText(error) })
        .eq("id", body.push_campaign_id);
    }
    return jsonResponse({ error: errorText(error) }, 500);
  }
});

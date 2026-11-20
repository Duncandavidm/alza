// Edge Function: award-habit-points (job diario, ~8:15 a.m. de Panama)
//
// 1. Suma los PUNTOS por buenos habitos con public.award_habit_points():
//    toda la regla vive en SQL (dias anotados, aportes de ahorro maduros,
//    presupuestos cumplidos, tope mensual). Nada lo calcula el iPhone, asi
//    que nadie puede inflar sus puntos desde la app.
// 2. Aplica las campañas de marcas a las facturas recien verificadas y
//    libera el cashback retenido que ya respaldan los ingresos.
// 3. Avisa por push a quien ya le alcanza para un premio que antes no
//    podia canjear (puntos o cashback, segun el comercio). Cada premio se
//    avisa una sola vez por persona (reward_unlock_notifications).
//
// 4. Anuncia los comercios aliados nuevos (una vez, a quien acepto
//    recibir ofertas) y recuerda escanear la factura a quien uso un
//    descuento de aliado hace 1 a 24 horas (migracion 0067).
//
// Corre despues de verify-dgi-receipt (8:00), para que el cashback recien
// confirmado tambien cuente. Ademas corre cada hora con {"mode":"hourly"},
// que solo manda los recordatorios de factura. Exige x-admin-secret;
// verify_jwt: false.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendPushToUser, sendPushToUsers } from "./apns.ts";

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

interface UnlockedItem {
  id: string;
  name: string;
  merchant: string;
  cost: number;
  currency: "puntos" | "cashback";
}

function unlockMessage(items: UnlockedItem[]): { title: string; body: string } {
  if (items.length === 1) {
    const item = items[0];
    const how = item.currency === "puntos" ? "tus puntos" : "tu cashback";
    return {
      title: `¡Ya puedes canjear un premio! 🎁`,
      body: `Te alcanza para ${item.name} en ${item.merchant} con ${how}. Toca para canjearlo.`,
    };
  }
  const names = items.slice(0, 2).map((item) => item.name).join(" y ");
  return {
    title: `¡Ya te alcanza para ${items.length} premios! 🎁`,
    body: `Entre ellos ${names}. Toca para ver los comercios aliados.`,
  };
}

type Supabase = ReturnType<typeof createClient>;

/// "¿Pediste tu factura en Café X?" una sola vez por uso de descuento.
async function sendBenefitInvoiceReminders(supabase: Supabase): Promise<number> {
  const { data, error } = await supabase.rpc("benefit_invoice_reminders_pending");
  if (error) {
    console.error("benefit_invoice_reminders_pending", error.message);
    return 0;
  }
  let sent = 0;
  for (const row of (data ?? []) as { redemption_id: string; user_id: string; merchant: string }[]) {
    // Se marca antes de enviar: si el push falla no se reintenta (es un extra).
    const { error: markError } = await supabase
      .from("reward_redemptions")
      .update({ invoice_reminder_sent_at: new Date().toISOString() })
      .eq("id", row.redemption_id)
      .is("invoice_reminder_sent_at", null);
    if (markError) {
      console.error("No se pudo marcar el recordatorio", markError.message);
      continue;
    }
    const result = await sendPushToUser(supabase, row.user_id, {
      title: `¿Pediste tu factura en ${row.merchant}? 🧾`,
      body: "Escanéala en MonAvi y gana cashback, además del descuento que ya usaste.",
      data: { screen: "home" },
      threadId: "monavi-facturas",
    });
    if (result.sent > 0) sent++;
  }
  return sent;
}

/// Comercio aliado nuevo: un solo aviso a quien acepto recibir ofertas.
async function announceNewPartners(supabase: Supabase): Promise<number> {
  const { data, error } = await supabase.rpc("partner_announcements_pending");
  if (error) {
    console.error("partner_announcements_pending", error.message);
    return 0;
  }
  const pending = (data ?? []) as { merchant_id: string; name: string; benefit: string | null }[];
  if (pending.length === 0) return 0;

  const { data: audience, error: audienceError } = await supabase.rpc("segment_user_ids", { p_segment: {} });
  if (audienceError) {
    console.error("segment_user_ids", audienceError.message);
    return 0;
  }
  const userIds = ((audience ?? []) as { user_id: string }[]).map((row) => row.user_id);

  let people = 0;
  for (const merchant of pending) {
    // Se marca primero: un aliado nunca se anuncia dos veces.
    const { error: markError } = await supabase
      .from("partner_merchants")
      .update({ announced_at: new Date().toISOString() })
      .eq("id", merchant.merchant_id)
      .is("announced_at", null);
    if (markError) {
      console.error("No se pudo marcar el anuncio", markError.message);
      continue;
    }
    const message = merchant.benefit
      ? {
        title: `Nuevo aliado: ${merchant.name} 🎉`,
        body: `${merchant.benefit} por ser de MonAvi. Pide tu factura fiscal y gana cashback también.`,
      }
      : {
        title: `Nuevo aliado: ${merchant.name} 🎉`,
        body: "Ya puedes canjear premios ahí con tu cashback. Pide siempre tu factura fiscal y escanéala.",
      };
    try {
      const result = await sendPushToUsers(supabase, userIds, {
        ...message,
        data: { screen: "rewards" },
        threadId: "monavi-aliados",
      });
      people += result.people;
    } catch (pushError) {
      console.error("Anuncio de aliado nuevo", String(pushError));
    }
  }
  return people;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.headers.get("x-admin-secret") !== ADMIN_JOB_SECRET) {
    return jsonResponse({ error: "No autorizado" }, 401);
  }

  try {
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    let body: { mode?: string } = {};
    try { body = await req.json(); } catch { /* corrida diaria sin body */ }
    if (body.mode === "hourly") {
      const invoiceReminders = await sendBenefitInvoiceReminders(supabase);
      return jsonResponse({ mode: "hourly", invoice_reminders: invoiceReminders });
    }

    const { data: awarded, error: awardError } = await supabase.rpc("award_habit_points");
    if (awardError) throw awardError;

    // Campañas de marcas ("compra X y gana mas") sobre las facturas que la
    // DGI confirmo a las 8:00. Si falla, no frena lo demas.
    const { data: campaignsApplied, error: campaignError } = await supabase.rpc("apply_brand_campaigns_recent");
    if (campaignError) console.error("apply_brand_campaigns_recent", campaignError.message);

    // Cashback retenido por falta de ingresos registrados: se libera si ya
    // hay ingresos que respalden la compra (migracion 0045).
    const { data: released, error: releaseError } = await supabase.rpc("release_income_held_cashback");
    if (releaseError) console.error("release_income_held_cashback", releaseError.message);
    let releasedUsers = 0;
    for (const row of (released ?? []) as { user_id: string; released_cents: number }[]) {
      if (!row.released_cents) continue;
      releasedUsers++;
      await sendPushToUser(supabase, row.user_id, {
        title: "¡Ya tienes tu cashback! 💸",
        body: "Registraste tus ingresos y liberamos $" + (row.released_cents / 100).toFixed(2) +
          " de cashback pendiente. Úsalo en los comercios aliados.",
        data: { screen: "points" },
      });
    }

    const { data: unlocks, error: unlockError } = await supabase.rpc("reward_unlocks_to_notify");
    if (unlockError) throw unlockError;

    let usersNotified = 0;
    let pushSent = 0;
    for (const row of (unlocks ?? []) as { user_id: string; items: UnlockedItem[] }[]) {
      if (!row.items?.length) continue;
      const { title, body } = unlockMessage(row.items);
      const result = await sendPushToUser(supabase, row.user_id, {
        title,
        body,
        data: { screen: "rewards" },
        threadId: "monavi-premios",
      });
      pushSent += result.sent;
      if (result.sent > 0) usersNotified++;

      // Se marca aunque el push falle: el aviso es un extra, no se reintenta
      // cada dia (y la app igual muestra el premio como disponible).
      const { error: markError } = await supabase.rpc("mark_reward_unlocks_notified", {
        p_user_id: row.user_id,
        p_item_ids: row.items.map((item) => item.id),
      });
      if (markError) console.error("No se pudo marcar el aviso", markError.message);
    }

    const partnerAnnouncementPeople = await announceNewPartners(supabase);
    const invoiceReminders = await sendBenefitInvoiceReminders(supabase);

    return jsonResponse({
      habit_events_awarded: awarded ?? 0,
      brand_bonuses: campaignsApplied ?? 0,
      cashback_released_users: releasedUsers,
      users_notified: usersNotified,
      push_sent: pushSent,
      partner_announcement_people: partnerAnnouncementPeople,
      invoice_reminders: invoiceReminders,
    });
  } catch (error) {
    console.error("award-habit-points fallo", error);
    return jsonResponse({ error: String((error as { message?: string })?.message ?? error) }, 500);
  }
});

// Edge Function: award-habit-points (job diario, ~8:15 a.m. de Panama)
//
// 1. Entrega los cupones por buenos habitos (issue_habit_coupons, 0068):
//    toda la regla vive en SQL, nada lo calcula el iPhone.
// 2. Aplica las campañas de marcas a las facturas recien verificadas y
//    libera el cashback retenido que ya respaldan los ingresos.
// 3. Avisa por push a quien ya le alcanza para un premio que antes no
//    podia canjear (puntos o cashback, segun el comercio). Cada premio se
//    avisa una sola vez por persona (reward_unlock_notifications).
//
// 4. Anuncia los comercios aliados nuevos (una vez, a quien acepto
//    recibir ofertas), con un aviso para cada persona: el descuento del
//    comercio y cuanto cashback le falta para su premio, con el logo. Y
//    recuerda escanear la factura a quien uso un descuento hace 1 a 24 h.
// Desde 1.0.3 ya no se suman puntos por habitos: los buenos habitos dan
// cupones (habit_coupon_rules) en vez de puntos.
//
// 5. Avisa una vez los cupones sin usar que vencen en las proximas 36
//    horas (0083).
//
// Corre despues de verify-dgi-receipt (8:00), para que el cashback recien
// confirmado tambien cuente. Ademas corre cada hora con {"mode":"hourly"},
// que solo manda los recordatorios de factura. Exige x-admin-secret;
// verify_jwt: false.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendPersonalizedPushes, sendPushToUser } from "./apns.ts";

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
  /// 0085: "porcentaje" (descuento) o "monto" (bono) se "desbloquean".
  type?: "producto" | "porcentaje" | "monto" | null;
  value?: number | string | null;
}

/// "20% de descuento" / "un bono de $20.00" / el nombre del producto.
function unlockLabel(item: UnlockedItem): string {
  const value = Number(item.value ?? 0);
  if (item.type === "porcentaje" && value > 0) return `${Number.isInteger(value) ? value : value.toFixed(1)}% de descuento`;
  if (item.type === "monto" && value > 0) return `un bono de $${value.toFixed(2)}`;
  return item.name;
}

function isUnlockable(item: UnlockedItem): boolean {
  return item.type === "porcentaje" || item.type === "monto";
}

function unlockMessage(items: UnlockedItem[]): { title: string; body: string } {
  if (items.length === 1) {
    const item = items[0];
    const how = item.currency === "puntos" ? "tu saldo" : "tu cashback";
    if (isUnlockable(item)) {
      return {
        title: item.type === "monto" ? "Bono desbloqueado 🔓" : "Descuento desbloqueado 🔓",
        body: `Ya puedes activar ${unlockLabel(item)} en ${item.merchant} con ${how}. Ábrelo en MonAvi para usarlo.`,
      };
    }
    return {
      title: "Premio disponible 🎁",
      body: `Ya puedes canjear ${item.name} en ${item.merchant} con ${how}. Ábrelo en MonAvi para canjearlo.`,
    };
  }
  const names = items.slice(0, 2).map((item) => `${unlockLabel(item)} en ${item.merchant}`).join(" y ");
  return {
    title: `${items.length} beneficios desbloqueados 🔓`,
    body: `Entre ellos, ${names}. Ábrelos en MonAvi para usarlos.`,
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
  if (userIds.length === 0) return 0;

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
    const { data: rows, error: rowsError } = await supabase.rpc("merchant_push_for_users", {
      p_merchant_id: merchant.merchant_id,
      p_user_ids: userIds,
    });
    if (rowsError) {
      console.error("merchant_push_for_users", rowsError.message);
      continue;
    }
    const messages = ((rows ?? []) as { user_id: string; title: string; body: string; image_url: string | null }[])
      .map((row) => ({ userId: row.user_id, title: row.title, body: row.body, imageUrl: row.image_url }));
    const result = await sendPersonalizedPushes(supabase, messages, {
      data: { screen: "rewards" },
      threadId: "monavi-aliados",
    });
    people += result.people;
  }
  return people;
}

/// Cupones por buenos habitos (o "para todos"): uno por regla y periodo,
/// cada uno con su aviso para que la persona entre a ver su codigo.
async function issueCouponsWithPush(supabase: Supabase): Promise<{ issued: number; pushes: number }> {
  const { data: coupons, error: couponError } = await supabase.rpc("issue_habit_coupons");
  if (couponError) console.error("issue_habit_coupons", couponError.message);
  let pushes = 0;
  for (const row of (coupons ?? []) as {
    user_id: string; coupon_name: string; merchant: string; reason: string; expires_at: string; image_url: string | null;
  }[]) {
    const until = new Date(row.expires_at).toLocaleDateString("es-PA", { day: "2-digit", month: "2-digit", timeZone: "America/Panama" });
    const result = await sendPushToUser(supabase, row.user_id, {
      title: `🎁 Tienes un cupón nuevo: ${row.coupon_name} en ${row.merchant}`,
      body: `Te lo ganaste ${row.reason}. Toca para ver tu código y úsalo en caja antes del ${until}.`,
      data: { screen: "redemptions" },
      threadId: "monavi-regalos",
      imageUrl: row.image_url,
    });
    if (result.sent > 0) pushes++;
  }
  return { issued: (coupons ?? []).length, pushes };
}

function panamaDay(date: Date): string {
  return date.toLocaleDateString("en-CA", { timeZone: "America/Panama" });
}

/// "Tu 15% en Café La Esquina vence mañana": una sola vez por cupón.
async function sendExpiringCouponReminders(supabase: Supabase): Promise<number> {
  const { data, error } = await supabase.rpc("coupons_expiring_soon");
  if (error) {
    console.error("coupons_expiring_soon", error.message);
    return 0;
  }
  const today = panamaDay(new Date());
  let sent = 0;
  for (const row of (data ?? []) as {
    redemption_id: string; user_id: string; coupon: string; merchant: string; expires_at: string; image_url: string | null;
  }[]) {
    const { error: markError } = await supabase
      .from("reward_redemptions")
      .update({ expiry_reminder_sent_at: new Date().toISOString() })
      .eq("id", row.redemption_id)
      .is("expiry_reminder_sent_at", null);
    if (markError) {
      console.error("No se pudo marcar el aviso de vencimiento", markError.message);
      continue;
    }
    const expires = new Date(row.expires_at);
    const when = panamaDay(expires) === today
      ? "vence hoy a las " + expires.toLocaleTimeString("es-PA", { hour: "numeric", minute: "2-digit", timeZone: "America/Panama" })
      : "vence mañana";
    const result = await sendPushToUser(supabase, row.user_id, {
      title: `⏰ Tu ${row.coupon} en ${row.merchant} ${when}`,
      body: "Úsalo antes de que se venza: toca para ver tu código y muéstralo en caja.",
      data: { screen: "redemptions" },
      threadId: "monavi-regalos",
      imageUrl: row.image_url,
    });
    if (result.sent > 0) sent++;
  }
  return sent;
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
    // El panel lo llama al crear o activar un cupon: se entrega ya, sin
    // esperar a la corrida diaria.
    if (body.mode === "coupons") {
      const coupons = await issueCouponsWithPush(supabase);
      return jsonResponse({ mode: "coupons", habit_coupons: coupons.issued, habit_coupon_pushes: coupons.pushes });
    }
    if (body.mode === "hourly") {
      const invoiceReminders = await sendBenefitInvoiceReminders(supabase);
      return jsonResponse({ mode: "hourly", invoice_reminders: invoiceReminders });
    }

    // Cupones por buenos habitos: uno por regla y periodo, con aviso.
    const coupons = await issueCouponsWithPush(supabase);

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
    const expiringReminders = await sendExpiringCouponReminders(supabase);

    return jsonResponse({
      habit_coupons: coupons.issued,
      habit_coupon_pushes: coupons.pushes,
      brand_bonuses: campaignsApplied ?? 0,
      cashback_released_users: releasedUsers,
      users_notified: usersNotified,
      push_sent: pushSent,
      partner_announcement_people: partnerAnnouncementPeople,
      invoice_reminders: invoiceReminders,
      expiring_coupon_reminders: expiringReminders,
    });
  } catch (error) {
    console.error("award-habit-points fallo", error);
    return jsonResponse({ error: String((error as { message?: string })?.message ?? error) }, 500);
  }
});

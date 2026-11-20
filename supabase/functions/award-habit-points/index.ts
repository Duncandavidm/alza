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
// Corre despues de verify-dgi-receipt (8:00), para que el cashback recien
// confirmado tambien cuente. Exige x-admin-secret; verify_jwt: false.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendPushToUser } from "./apns.ts";

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.headers.get("x-admin-secret") !== ADMIN_JOB_SECRET) {
    return jsonResponse({ error: "No autorizado" }, 401);
  }

  try {
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

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

    return jsonResponse({ habit_events_awarded: awarded ?? 0, brand_bonuses: campaignsApplied ?? 0, cashback_released_users: releasedUsers, users_notified: usersNotified, push_sent: pushSent });
  } catch (error) {
    console.error("award-habit-points fallo", error);
    return jsonResponse({ error: String((error as { message?: string })?.message ?? error) }, 500);
  }
});

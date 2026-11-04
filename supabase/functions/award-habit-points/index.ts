// Edge Function: award-habit-points
//
// "Habitos financieros" (B1, puntos de bajo valor, sin verificacion
// bancaria, con tope estricto): registrar gastos varios dias seguidos
// (racha), cumplir un presupuesto semanal, terminar el mes sin pasarse
// del presupuesto de una categoria. Solo cuenta lo que esta app puede
// medir ella misma a partir de `transactions`/`budgets` — nada
// autodeclarado.
//
// Igual que reconcile-card-transactions: job operativo (cron), no lo
// llama la app con el JWT de un usuario. Exige `x-admin-secret`
// (ADMIN_JOB_SECRET). Desplegar con verify_jwt: false.
//
// Simplificacion documentada: los limites de "dia"/"semana"/"mes" se
// calculan en UTC, no en la zona horaria del dispositivo del usuario —
// para una app de finanzas reales esto importaria, pero para puntos de
// gamificacion con tope bajo el margen de error (como mucho un dia cerca
// de medianoche) es aceptable. Semana = lunes a domingo (ISO 8601), no
// el criterio dependiente de locale que usa `Calendar.current` en el
// cliente — puede no coincidir exactamente con lo que el cliente pinta
// como "esta semana" en Presupuestos.
//
// NOTA: no se pudo probar contra un runtime Deno real en este entorno.
// La logica (racha, presupuesto semanal/mensual cumplido, tope mensual)
// se valido paso a paso con SQL real contra la base (ver reporte de la
// sesion).

import { createClient } from "jsr:@supabase/supabase-js@2";

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

function utcDateOnly(d: Date): string {
  return d.toISOString().slice(0, 10); // yyyy-MM-dd
}

function addDaysUTC(d: Date, days: number): Date {
  const copy = new Date(d.getTime());
  copy.setUTCDate(copy.getUTCDate() + days);
  return copy;
}

function startOfUTCDay(d: Date): Date {
  const copy = new Date(d.getTime());
  copy.setUTCHours(0, 0, 0, 0);
  return copy;
}

/// Lunes de la semana ISO que contiene `d` (00:00 UTC).
function mondayOfWeekUTC(d: Date): Date {
  const day = d.getUTCDay(); // 0=domingo .. 6=sabado
  const diffToMonday = day === 0 ? -6 : 1 - day;
  return startOfUTCDay(addDaysUTC(d, diffToMonday));
}

function startOfUTCMonth(d: Date): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1));
}

async function getRule(
  supabase: ReturnType<typeof createClient>,
  source: string,
  key: string,
  fallback: number,
): Promise<number> {
  const { data } = await supabase
    .from("points_rules")
    .select("value")
    .eq("source", source)
    .eq("key", key)
    .maybeSingle();
  const value = data?.value;
  return typeof value === "number" ? value : fallback;
}

interface Candidate {
  points: number;
  externalRef: string;
  occurredAt: string;
  metadata: Record<string, unknown>;
}

/// Racha de dias consecutivos (hasta ayer, UTC) con al menos una
/// transaccion registrada. Si la racha es multiplo de 7, es candidata a
/// puntos — una sola vez por cada semana completa de racha (el
/// external_ref cambia cada vez que la racha avanza 7 dias mas, asi que
/// nunca se vuelve a otorgar por el mismo tramo).
async function streakCandidate(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  streakPoints: number,
  now: Date,
): Promise<Candidate | null> {
  const windowStart = addDaysUTC(now, -60);
  const { data } = await supabase
    .from("transactions")
    .select("occurred_at")
    .eq("user_id", userId)
    .gte("occurred_at", windowStart.toISOString());

  const days = new Set((data ?? []).map((row: { occurred_at: string }) => utcDateOnly(new Date(row.occurred_at))));

  let streak = 0;
  let cursor = startOfUTCDay(addDaysUTC(now, -1)); // ayer
  while (days.has(utcDateOnly(cursor))) {
    streak++;
    cursor = addDaysUTC(cursor, -1);
  }

  if (streak === 0 || streak % 7 !== 0) return null;

  const streakEndDate = utcDateOnly(addDaysUTC(now, -1));
  return {
    points: streakPoints,
    externalRef: `habito:racha:${userId}:${streakEndDate}`,
    occurredAt: now.toISOString(),
    metadata: { streakDays: streak },
  };
}

async function budgetSpent(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  category: string,
  start: Date,
  end: Date,
): Promise<number> {
  const { data } = await supabase
    .from("transactions")
    .select("amount")
    .eq("user_id", userId)
    .eq("category", category)
    .eq("movement_type", "gasto")
    .gte("occurred_at", start.toISOString())
    .lt("occurred_at", end.toISOString());
  return (data ?? []).reduce((sum: number, row: { amount: number }) => sum + Math.abs(Number(row.amount)), 0);
}

async function weeklyBudgetCandidates(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  points: number,
  now: Date,
): Promise<Candidate[]> {
  const thisWeekStart = mondayOfWeekUTC(now);
  const lastWeekStart = addDaysUTC(thisWeekStart, -7);
  const lastWeekEnd = thisWeekStart;

  const { data: budgets } = await supabase
    .from("budgets")
    .select("id, category, limit_amount")
    .eq("user_id", userId)
    .eq("period", "weekly");

  const candidates: Candidate[] = [];
  for (const budget of budgets ?? []) {
    const spent = await budgetSpent(supabase, userId, budget.category as string, lastWeekStart, lastWeekEnd);
    if (spent <= Number(budget.limit_amount)) {
      candidates.push({
        points,
        externalRef: `habito:weekly_budget:${budget.id}:${utcDateOnly(lastWeekStart)}`,
        occurredAt: now.toISOString(),
        metadata: { budgetId: budget.id, category: budget.category, spent, weekStart: utcDateOnly(lastWeekStart) },
      });
    }
  }
  return candidates;
}

async function monthlyBudgetCandidates(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  points: number,
  now: Date,
): Promise<Candidate[]> {
  const thisMonthStart = startOfUTCMonth(now);
  const lastMonthStart = new Date(Date.UTC(thisMonthStart.getUTCFullYear(), thisMonthStart.getUTCMonth() - 1, 1));
  const lastMonthEnd = thisMonthStart;

  const { data: budgets } = await supabase
    .from("budgets")
    .select("id, category, limit_amount")
    .eq("user_id", userId)
    .eq("period", "monthly");

  const candidates: Candidate[] = [];
  for (const budget of budgets ?? []) {
    const spent = await budgetSpent(supabase, userId, budget.category as string, lastMonthStart, lastMonthEnd);
    if (spent <= Number(budget.limit_amount)) {
      candidates.push({
        points,
        externalRef: `habito:monthly_budget:${budget.id}:${utcDateOnly(lastMonthStart)}`,
        occurredAt: now.toISOString(),
        metadata: { budgetId: budget.id, category: budget.category, spent, monthStart: utcDateOnly(lastMonthStart) },
      });
    }
  }
  return candidates;
}

async function currentMonthHabitPoints(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  now: Date,
): Promise<number> {
  const monthStart = startOfUTCMonth(now);
  const { data } = await supabase
    .from("points_ledger")
    .select("points")
    .eq("user_id", userId)
    .eq("source", "habito")
    .gte("occurred_at", monthStart.toISOString());
  return (data ?? []).reduce((sum: number, row: { points: number }) => sum + row.points, 0);
}

async function processUser(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  rules: { streakPoints: number; weeklyPoints: number; monthlyPoints: number; monthlyCap: number },
  now: Date,
): Promise<{ awarded: Candidate[]; skippedForCap: Candidate[] }> {
  const candidates: Candidate[] = [];
  const streak = await streakCandidate(supabase, userId, rules.streakPoints, now);
  if (streak) candidates.push(streak);
  candidates.push(...(await weeklyBudgetCandidates(supabase, userId, rules.weeklyPoints, now)));
  candidates.push(...(await monthlyBudgetCandidates(supabase, userId, rules.monthlyPoints, now)));

  let runningTotal = await currentMonthHabitPoints(supabase, userId, now);
  const awarded: Candidate[] = [];
  const skippedForCap: Candidate[] = [];

  for (const candidate of candidates) {
    if (runningTotal + candidate.points > rules.monthlyCap) {
      skippedForCap.push(candidate);
      continue;
    }
    const { error } = await supabase.rpc("award_points", {
      p_user_id: userId,
      p_source: "habito",
      p_external_ref: candidate.externalRef,
      p_points: candidate.points,
      p_status: "confirmado",
      p_occurred_at: candidate.occurredAt,
      p_metadata: candidate.metadata,
    });
    if (error) throw error;
    // Siempre se suma al total corriente de ESTA corrida, haya sido un
    // insert nuevo o un no-op idempotente sobre una fila que ya
    // existia — asi el chequeo de tope de abajo nunca se pasa dentro de
    // la misma corrida, aunque sea un poco conservador si algun
    // candidato ya estaba otorgado de una corrida anterior.
    runningTotal += candidate.points;
    awarded.push(candidate);
  }

  return { awarded, skippedForCap };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  if (req.headers.get("x-admin-secret") !== ADMIN_JOB_SECRET) {
    return jsonResponse({ error: "No autorizado" }, 401);
  }

  try {
    const body = await req.json().catch(() => ({}));
    const singleUserId = typeof body?.user_id === "string" ? body.user_id : null;

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const now = new Date();

    const rules = {
      streakPoints: await getRule(supabase, "habito", "streak_points_per_week", 20),
      weeklyPoints: await getRule(supabase, "habito", "weekly_budget_points", 15),
      monthlyPoints: await getRule(supabase, "habito", "monthly_budget_points", 30),
      monthlyCap: await getRule(supabase, "habito", "monthly_cap_points", 200),
    };

    let userIds: string[];
    if (singleUserId) {
      userIds = [singleUserId];
    } else {
      const { data: profiles, error } = await supabase.from("profiles").select("id");
      if (error) throw error;
      userIds = (profiles ?? []).map((p: { id: string }) => p.id);
    }

    const results: Record<string, { awarded: number; skippedForCap: number }> = {};
    for (const userId of userIds) {
      const { awarded, skippedForCap } = await processUser(supabase, userId, rules, now);
      results[userId] = { awarded: awarded.length, skippedForCap: skippedForCap.length };
    }

    return jsonResponse({ processedUsers: userIds.length, results });
  } catch (error) {
    console.error(error);
    return jsonResponse({ error: String(error) }, 500);
  }
});

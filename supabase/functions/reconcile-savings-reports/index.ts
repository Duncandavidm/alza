// Edge Function: reconcile-savings-reports
//
// "Ahorro verificado" (B2, puntos de alto valor, SOLO con verificacion
// del banco patrocinador): procesa reportes de saldo PROMEDIO mensual
// que manda un banco (o el mock), los cruza contra las inscripciones
// activas por (banco, identificador de cuenta acordado) y decide si la
// meta del mes se cumplio. Los puntos nacen 'pendiente' y solo se
// confirman cuando el reporte del MES SIGUIENTE demuestra que el dinero
// se quedo ahi la permanencia minima configurada — si en vez de eso el
// saldo cae mucho, se anulan con un movimiento negativo nuevo (nunca se
// edita el original).
//
// Igual que las otras 2 Edge Functions operativas de este modulo: no la
// llama la app con JWT de usuario, exige `x-admin-secret`
// (ADMIN_JOB_SECRET), verify_jwt: false.
//
// NOTA: no se pudo probar contra un runtime Deno real en este entorno —
// la logica (match, meta cumplida/no cumplida, confirmacion/anulacion
// por retencion) se valido paso a paso con SQL real contra la base (ver
// reporte de la sesion).

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
  return d.toISOString().slice(0, 10);
}

function monthStart(year: number, month0: number): Date {
  return new Date(Date.UTC(year, month0, 1));
}

function addMonthsUTC(d: Date, months: number): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + months, 1));
}

// ---------------------------------------------------------------------
// ProveedorVerificacionAhorro: interfaz comun, 3 implementaciones.
// ---------------------------------------------------------------------

interface SavingsReportRecord {
  externalAccountRef: string;
  periodMonth: string; // yyyy-MM-01
  avgBalance: number;
  providedAt: string;
}

interface SavingsVerificationProvider {
  readonly name: string;
  fetchPending(bankPartnerId: string, supabase: ReturnType<typeof createClient>): Promise<SavingsReportRecord[]>;
}

/// 1. Mock — un reporte de ejemplo para probar el pipeline.
class MockSavingsVerificationProvider implements SavingsVerificationProvider {
  readonly name = "mock";
  async fetchPending(): Promise<SavingsReportRecord[]> {
    const now = new Date();
    const lastMonth = addMonthsUTC(monthStart(now.getUTCFullYear(), now.getUTCMonth()), -1);
    return [
      {
        externalAccountRef: "mock-account-1",
        periodMonth: utcDateOnly(lastMonth),
        avgBalance: 150,
        providedAt: now.toISOString(),
      },
    ];
  }
}

/// 2. Reporte del banco — el banco patrocinador sube (panel admin, Fase
/// 4, o API aparte, todavia sin construir) filas a `savings_bank_reports`
/// con source='bank_report' y match_status='pending_match'. Este
/// proveedor solo LEE esas filas.
class BankReportSavingsProvider implements SavingsVerificationProvider {
  readonly name = "bank_report";
  async fetchPending(
    bankPartnerId: string,
    supabase: ReturnType<typeof createClient>,
  ): Promise<SavingsReportRecord[]> {
    const { data, error } = await supabase
      .from("savings_bank_reports")
      .select("external_account_ref, period_month, avg_balance, provided_at")
      .eq("bank_partner_id", bankPartnerId)
      .eq("source", "bank_report")
      .eq("match_status", "pending_match");
    if (error) throw error;
    return (data ?? []).map((row: Record<string, unknown>) => ({
      externalAccountRef: row.external_account_ref as string,
      periodMonth: row.period_month as string,
      avgBalance: Number(row.avg_balance),
      providedAt: row.provided_at as string,
    }));
  }
}

/// 3. API bancaria directa — vacio a proposito. TODO(David): cuando haya
/// un acuerdo firmado con un banco que exponga API, implementar la
/// llamada aqui. Esta funcion nunca debe pedir ni guardar el numero de
/// cuenta real — solo el identificador opaco que el banco acuerde.
class BankApiPlaceholderProvider implements SavingsVerificationProvider {
  readonly name = "bank_api_placeholder";
  async fetchPending(): Promise<SavingsReportRecord[]> {
    return [];
  }
}

function resolveProvider(name: string): SavingsVerificationProvider {
  switch (name) {
    case "mock":
      return new MockSavingsVerificationProvider();
    case "bank_report":
      return new BankReportSavingsProvider();
    case "bank_api_placeholder":
      return new BankApiPlaceholderProvider();
    default:
      throw new Error(`Proveedor desconocido: ${name}`);
  }
}

// ---------------------------------------------------------------------
// Reconciliacion
// ---------------------------------------------------------------------

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

/// Resuelve el PERIODO ANTERIOR de esta inscripcion (confirma o anula
/// sus puntos 'pendiente'), usando el reporte del periodo ACTUAL como
/// evidencia de si el dinero se quedo o se retiro. Nunca edita el
/// movimiento original — siempre inserta uno nuevo (reversa, y si
/// aplica, un 'confirmado' aparte).
async function resolveRetention(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  enrollmentId: string,
  currentPeriodMonth: string,
  currentAvgBalance: number,
  minRetentionDays: number,
  withdrawalThresholdFraction: number,
  now: Date,
) {
  const currentPeriodStart = new Date(`${currentPeriodMonth}T00:00:00.000Z`);
  const prevPeriodStart = addMonthsUTC(currentPeriodStart, -1);
  const prevPeriodMonth = utcDateOnly(prevPeriodStart);

  const { data: prevGoal } = await supabase
    .from("sponsored_savings_goals")
    .select("id, target_amount, status")
    .eq("enrollment_id", enrollmentId)
    .eq("period_month", prevPeriodMonth)
    .maybeSingle();
  if (!prevGoal || prevGoal.status !== "met") return;

  const pendingRef = `ahorro:${enrollmentId}:${prevPeriodMonth}`;
  const retentionRef = `ahorro:${enrollmentId}:${prevPeriodMonth}:retention`;

  const { data: alreadyResolved } = await supabase
    .from("points_ledger")
    .select("id")
    .eq("external_ref", retentionRef)
    .maybeSingle();
  if (alreadyResolved) return; // ya se resolvio en una corrida anterior

  const { data: pendingEntry } = await supabase
    .from("points_ledger")
    .select("points")
    .eq("external_ref", pendingRef)
    .eq("status", "pendiente")
    .maybeSingle();
  if (!pendingEntry) return; // nada pendiente que resolver

  // El periodo anterior termina al empezar el periodo actual.
  const daysSincePeriodEnd = (now.getTime() - currentPeriodStart.getTime()) / (1000 * 60 * 60 * 24);
  if (daysSincePeriodEnd < minRetentionDays) return; // todavia no pasa la permanencia minima

  const pendingPoints = Number(pendingEntry.points);
  const withdrew = currentAvgBalance < Number(prevGoal.target_amount) * (1 - withdrawalThresholdFraction);

  // Siempre se revierte el 'pendiente' original (nunca se edita) — si NO
  // hubo retiro, se acompaña de una fila 'confirmado' nueva con los
  // mismos puntos. IMPORTANTE: esta reversa debe llevar status
  // 'pendiente' (no 'anulado') porque points_balances suma por status —
  // una reversa 'anulado' no resta de ningun bucket mostrado y deja
  // puntos pendientes fantasma para siempre. 'anulado' se reserva para
  // ajustes que no cancelan una fila existente del ledger.
  await supabase.rpc("award_points", {
    p_user_id: userId,
    p_source: "ahorro",
    p_external_ref: retentionRef,
    p_points: -pendingPoints,
    p_status: "pendiente",
    p_occurred_at: now.toISOString(),
    p_metadata: { prevPeriodMonth, withdrew, reason: withdrew ? "retiro antes de la permanencia minima" : "convertido a confirmado" },
  });

  if (!withdrew) {
    await supabase.rpc("award_points", {
      p_user_id: userId,
      p_source: "ahorro",
      p_external_ref: `${pendingRef}:confirmed`,
      p_points: pendingPoints,
      p_status: "confirmado",
      p_occurred_at: now.toISOString(),
      p_metadata: { prevPeriodMonth },
    });
  }
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
    const providerName = typeof body?.provider === "string" ? body.provider : "mock";
    const bankPartnerId = typeof body?.bank_partner_id === "string" ? body.bank_partner_id : null;
    if (!bankPartnerId) {
      return jsonResponse({ error: "bank_partner_id es requerido" }, 400);
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const now = new Date();

    const pointsPerGoal = await getRule(supabase, "ahorro", "points_per_goal_met", 500);
    const minRetentionDays = await getRule(supabase, "ahorro", "min_retention_days", 30);
    const withdrawalThresholdFraction = await getRule(supabase, "ahorro", "withdrawal_threshold_fraction", 0.5);

    const provider = resolveProvider(providerName);
    const records = await provider.fetchPending(bankPartnerId, supabase);

    let processed = 0;
    const errors: string[] = [];

    for (const record of records) {
      try {
        const { data: row, error: upsertError } = await supabase
          .from("savings_bank_reports")
          .upsert(
            {
              bank_partner_id: bankPartnerId,
              external_account_ref: record.externalAccountRef,
              period_month: record.periodMonth,
              avg_balance: record.avgBalance,
              source: providerName,
              provided_at: record.providedAt,
            },
            { onConflict: "bank_partner_id,external_account_ref,period_month" },
          )
          .select()
          .single();
        if (upsertError) throw upsertError;

        if (row.match_status !== "pending_match") {
          processed++;
          continue;
        }

        const { data: enrollment } = await supabase
          .from("sponsored_savings_enrollments")
          .select("id, user_id")
          .eq("bank_partner_id", bankPartnerId)
          .eq("external_account_ref", record.externalAccountRef)
          .eq("status", "active")
          .maybeSingle();

        if (!enrollment) {
          await supabase.from("savings_bank_reports").update({
            match_status: "unmatched",
            match_note: "No hay una inscripcion activa con ese identificador de cuenta.",
            reconciled_at: now.toISOString(),
          }).eq("id", row.id);
          processed++;
          continue;
        }

        const { data: goal } = await supabase
          .from("sponsored_savings_goals")
          .select("id, target_amount")
          .eq("enrollment_id", enrollment.id)
          .eq("period_month", record.periodMonth)
          .maybeSingle();

        if (!goal) {
          await supabase.from("savings_bank_reports").update({
            match_status: "matched",
            enrollment_id: enrollment.id,
            match_note: "No hay meta creada para ese mes — sin puntos.",
            reconciled_at: now.toISOString(),
          }).eq("id", row.id);
          processed++;
          continue;
        }

        const met = record.avgBalance >= Number(goal.target_amount);
        await supabase.from("sponsored_savings_goals").update({ status: met ? "met" : "missed" }).eq("id", goal.id);

        let pointsAwarded: number | null = null;
        if (met) {
          pointsAwarded = pointsPerGoal;
          await supabase.rpc("award_points", {
            p_user_id: enrollment.user_id,
            p_source: "ahorro",
            p_external_ref: `ahorro:${enrollment.id}:${record.periodMonth}`,
            p_points: pointsPerGoal,
            p_status: "pendiente",
            p_occurred_at: record.providedAt,
            p_metadata: { enrollmentId: enrollment.id, goalId: goal.id, avgBalance: record.avgBalance, targetAmount: goal.target_amount },
          });
        }

        await resolveRetention(
          supabase,
          enrollment.user_id as string,
          enrollment.id as string,
          record.periodMonth,
          record.avgBalance,
          minRetentionDays,
          withdrawalThresholdFraction,
          now,
        );

        await supabase.from("savings_bank_reports").update({
          match_status: "matched",
          enrollment_id: enrollment.id,
          goal_id: goal.id,
          points_awarded: pointsAwarded,
          reconciled_at: now.toISOString(),
        }).eq("id", row.id);

        processed++;
      } catch (recordError) {
        errors.push(`${record.externalAccountRef}/${record.periodMonth}: ${String(recordError)}`);
      }
    }

    return jsonResponse({ provider: providerName, fetched: records.length, processed, errors });
  } catch (error) {
    console.error(error);
    return jsonResponse({ error: String(error) }, 500);
  }
});

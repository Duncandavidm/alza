// Edge Function: reconcile-card-transactions
//
// "Tarjeta en comercios aliados": procesa compras con tarjeta reportadas
// por un proveedor (ver ProveedorTransaccionesTarjeta abajo), las cruza
// contra las tarjetas vinculadas por los usuarios (ultimos4 + marca,
// solo entre tarjetas activas) y, si hay EXACTAMENTE un usuario posible,
// crea el gasto y acredita puntos via award_points(). Si hay 0 o 2+
// candidatos, la fila queda 'unmatched'/'ambiguous' sin puntos, visible
// solo desde el panel admin (Fase 4).
//
// A diferencia del resto de las funciones de este proyecto, esta NO la
// llama la app con el JWT de un usuario — es un job operativo (cron o
// panel admin). Por eso NO usa getVerifiedUserId ni verify_jwt de la
// plataforma; en su lugar exige un secreto compartido en el header
// `x-admin-secret` (ADMIN_JOB_SECRET). Desplegar con verify_jwt: false.
//
// Seguridad de tarjetas (no negociable, ver spec del modulo): esta
// funcion NUNCA ve numero completo, CVV ni vencimiento — linked_cards
// solo guarda marca + ultimos 4 + alias, y los proveedores de abajo solo
// reportan lo mismo.
//
// NOTA: no se pudo probar contra un runtime Deno real en este entorno.
// La logica de reconciliacion si se probo end-to-end contra la base real
// via el proveedor mock, invocando las mismas consultas SQL a mano
// (ver el reporte de pruebas en el mensaje de la sesion).

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

// ---------------------------------------------------------------------
// ProveedorTransaccionesTarjeta: interfaz comun, 3 implementaciones.
// ---------------------------------------------------------------------

interface CardTransactionRecord {
  providerTransactionId: string;
  merchantRuc: string;
  branch: string | null;
  amount: number;
  occurredAt: string; // ISO 8601
  cardLast4: string;
  cardBrand: "visa" | "mastercard" | "amex" | "other";
  reportStatus: "authorized" | "settled" | "reversed";
}

interface CardTransactionsProvider {
  readonly name: string;
  fetchPending(): Promise<CardTransactionRecord[]>;
}

/// 1. Mock — un par de compras de ejemplo, para probar el pipeline
/// completo sin depender de ningun comercio real.
class MockCardTransactionsProvider implements CardTransactionsProvider {
  readonly name = "mock";
  async fetchPending(): Promise<CardTransactionRecord[]> {
    return [
      {
        providerTransactionId: `mock-${Date.now()}`,
        merchantRuc: "155719930-2-2022",
        branch: "0002",
        amount: 18.5,
        occurredAt: new Date().toISOString(),
        cardLast4: "4242",
        cardBrand: "visa",
        reportStatus: "authorized",
      },
    ];
  }
}

/// 2. Reporte del comercio — el comercio aliado sube sus ventas (panel
/// admin, Fase 4, o API aparte, todavia sin construir) a filas de
/// `card_transactions` con provider='merchant_report' y
/// match_status='pending_match'. Este proveedor solo LEE esas filas; el
/// INGEST (crearlas) es responsabilidad del panel admin, no de esta
/// funcion.
class MerchantReportCardTransactionsProvider implements CardTransactionsProvider {
  readonly name = "merchant_report";
  constructor(private supabase: ReturnType<typeof createClient>) {}

  async fetchPending(): Promise<CardTransactionRecord[]> {
    const { data, error } = await this.supabase
      .from("card_transactions")
      .select("provider_transaction_id, merchant_ruc, branch, amount, occurred_at, card_last4, card_brand, report_status")
      .eq("provider", "merchant_report")
      .eq("match_status", "pending_match");
    if (error) throw error;
    return (data ?? []).map((row: Record<string, unknown>) => ({
      providerTransactionId: row.provider_transaction_id as string,
      merchantRuc: row.merchant_ruc as string,
      branch: (row.branch as string) ?? null,
      amount: Number(row.amount),
      occurredAt: row.occurred_at as string,
      cardLast4: row.card_last4 as string,
      cardBrand: row.card_brand as CardTransactionRecord["cardBrand"],
      reportStatus: row.report_status as CardTransactionRecord["reportStatus"],
    }));
  }
}

/// 3. Red/agregador real (Visa, Mastercard, u otro procesador) — vacio a
/// proposito. TODO(David): cuando haya un acuerdo firmado, implementar
/// la llamada a la API de la red aqui y mapear su respuesta a
/// CardTransactionRecord. Si esa integracion requiere vincular la
/// tarjeta completa, eso se hace con el SDK/webview SEGURO del
/// proveedor — nunca con un formulario propio de MonAvi.
class NetworkProviderPlaceholder implements CardTransactionsProvider {
  readonly name = "network_placeholder";
  async fetchPending(): Promise<CardTransactionRecord[]> {
    return [];
  }
}

function resolveProvider(
  name: string,
  supabase: ReturnType<typeof createClient>,
): CardTransactionsProvider {
  switch (name) {
    case "mock":
      return new MockCardTransactionsProvider();
    case "merchant_report":
      return new MerchantReportCardTransactionsProvider(supabase);
    case "network_placeholder":
      return new NetworkProviderPlaceholder();
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
): Promise<number | null> {
  const { data } = await supabase
    .from("points_rules")
    .select("value")
    .eq("source", source)
    .eq("key", key)
    .maybeSingle();
  if (!data) return null;
  const value = data.value;
  return typeof value === "number" ? value : null;
}

async function getDefaultAccountId(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<string | null> {
  const { data } = await supabase
    .from("accounts")
    .select("id")
    .eq("user_id", userId)
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  return (data?.id as string) ?? null;
}

async function markRow(
  supabase: ReturnType<typeof createClient>,
  id: string,
  fields: Record<string, unknown>,
) {
  await supabase
    .from("card_transactions")
    .update({ ...fields, reconciled_at: new Date().toISOString() })
    .eq("id", id);
}

async function reconcileRow(supabase: ReturnType<typeof createClient>, row: Record<string, unknown>) {
  const rowId = row.id as string;
  const cardBrand = row.card_brand as string;
  const cardLast4 = row.card_last4 as string;
  const merchantRuc = row.merchant_ruc as string;
  const amount = Number(row.amount);
  const occurredAt = row.occurred_at as string;
  const reportStatus = row.report_status as string;

  const { data: candidates, error: candidatesError } = await supabase
    .from("linked_cards")
    .select("id, user_id, account_id")
    .eq("brand", cardBrand)
    .eq("last4", cardLast4)
    .eq("status", "active");
  if (candidatesError) throw candidatesError;

  if (!candidates || candidates.length === 0) {
    await markRow(supabase, rowId, {
      match_status: "unmatched",
      match_note: "Ninguna tarjeta activa vinculada con esos ultimos 4 + marca.",
    });
    return;
  }
  if (candidates.length > 1) {
    await markRow(supabase, rowId, {
      match_status: "ambiguous",
      match_note: `${candidates.length} tarjetas activas coinciden con esos ultimos 4 + marca — no se puede asignar sin ambiguedad. Revisar en el panel admin.`,
    });
    return;
  }

  const candidate = candidates[0] as { id: string; user_id: string; account_id: string | null };

  const { data: merchant } = await supabase
    .from("partner_merchants")
    .select("id, status, name")
    .eq("ruc", merchantRuc)
    .maybeSingle();

  if (!merchant || merchant.status !== "active") {
    await markRow(supabase, rowId, {
      match_status: "matched",
      user_id: candidate.user_id,
      linked_card_id: candidate.id,
      match_note: "Tarjeta identificada, pero el comercio no es un aliado activo — sin puntos.",
    });
    return;
  }

  const { data: offer } = await supabase
    .from("partner_merchant_offers")
    .select("*")
    .eq("merchant_id", merchant.id)
    .eq("status", "active")
    .lte("starts_at", occurredAt)
    .or(`ends_at.is.null,ends_at.gte.${occurredAt}`)
    .order("starts_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!offer) {
    await markRow(supabase, rowId, {
      match_status: "matched",
      user_id: candidate.user_id,
      linked_card_id: candidate.id,
      merchant_id: merchant.id,
      match_note: "Comercio aliado sin oferta activa en esa fecha — sin puntos.",
    });
    return;
  }

  if (offer.min_amount && amount < Number(offer.min_amount)) {
    await markRow(supabase, rowId, {
      match_status: "matched",
      user_id: candidate.user_id,
      linked_card_id: candidate.id,
      merchant_id: merchant.id,
      match_note: `Compra de $${amount.toFixed(2)} no alcanza el minimo de $${Number(offer.min_amount).toFixed(2)} de la oferta.`,
    });
    return;
  }

  const rawPoints = offer.offer_type === "percent"
    ? amount * Number(offer.value)
    : Number(offer.value);
  const points = Math.max(0, Math.floor(rawPoints));

  if (points === 0) {
    await markRow(supabase, rowId, {
      match_status: "matched",
      user_id: candidate.user_id,
      linked_card_id: candidate.id,
      merchant_id: merchant.id,
      match_note: "La oferta no genero puntos para este monto.",
    });
    return;
  }

  if (offer.budget_total_points !== null && offer.budget_spent_points + points > offer.budget_total_points) {
    await supabase
      .from("partner_merchant_offers")
      .update({ status: "budget_exhausted" })
      .eq("id", offer.id);
    await markRow(supabase, rowId, {
      match_status: "matched",
      user_id: candidate.user_id,
      linked_card_id: candidate.id,
      merchant_id: merchant.id,
      match_note: "Presupuesto de la campaña agotado — sin puntos. Revisar con el comercio.",
    });
    return;
  }

  const dailyCap = await getRule(supabase, "tarjeta", "daily_cap_points_per_user");
  if (dailyCap !== null) {
    const dayStart = new Date(occurredAt);
    dayStart.setUTCHours(0, 0, 0, 0);
    const dayEnd = new Date(dayStart);
    dayEnd.setUTCDate(dayEnd.getUTCDate() + 1);

    const { data: todays } = await supabase
      .from("points_ledger")
      .select("points")
      .eq("user_id", candidate.user_id)
      .eq("source", "tarjeta")
      .gte("occurred_at", dayStart.toISOString())
      .lt("occurred_at", dayEnd.toISOString());
    const alreadyToday = (todays ?? []).reduce((sum: number, r: { points: number }) => sum + r.points, 0);
    if (alreadyToday + points > dailyCap) {
      await markRow(supabase, rowId, {
        match_status: "matched",
        user_id: candidate.user_id,
        linked_card_id: candidate.id,
        merchant_id: merchant.id,
        match_note: `Tope diario de puntos de tarjeta alcanzado (${alreadyToday}/${dailyCap}).`,
      });
      return;
    }
  }

  const externalRefBase = `tarjeta:${row.provider}:${row.provider_transaction_id}`;

  if (reportStatus === "reversed") {
    // Anula lo que se haya otorgado antes para esta transaccion (pendiente
    // o confirmado) con un movimiento negativo nuevo — nunca se edita el
    // original. IMPORTANTE: la reversa debe llevar el MISMO status que el
    // original (pendiente o confirmado), no 'anulado' — points_balances
    // suma por status, asi que una reversa 'anulado' no resta de ningun
    // lado y deja puntos fantasma. 'anulado' queda para ajustes que no
    // cancelan una fila existente del ledger.
    const { data: originalEntry } = await supabase
      .from("points_ledger")
      .select("status")
      .eq("source", "tarjeta")
      .eq("external_ref", externalRefBase)
      .maybeSingle();
    const reversalStatus = (originalEntry?.status as string) ?? "pendiente";

    await supabase.rpc("award_points", {
      p_user_id: candidate.user_id,
      p_source: "tarjeta",
      p_external_ref: `${externalRefBase}:reversed`,
      p_points: -points,
      p_status: reversalStatus,
      p_occurred_at: new Date().toISOString(),
      p_metadata: { merchant: merchant.name, original_ref: externalRefBase, reason: "anulado" },
    });
    await markRow(supabase, rowId, {
      match_status: "matched",
      user_id: candidate.user_id,
      linked_card_id: candidate.id,
      merchant_id: merchant.id,
      points_awarded: -points,
      match_note: "Reversa procesada — puntos anulados.",
    });
    return;
  }

  // Busca categoria/nombre en la tabla `merchants` (modulo "Facturas que
  // suman" — mismo RUC, reutilizado aqui en vez de duplicar el catalogo).
  const { data: merchantCategory } = await supabase
    .from("merchants")
    .select("category, name")
    .eq("ruc", merchantRuc)
    .maybeSingle();

  let transactionId: string | null = null;
  const accountId = candidate.account_id ?? (await getDefaultAccountId(supabase, candidate.user_id));

  if (accountId) {
    const { data: createdTx, error: txError } = await supabase
      .from("transactions")
      .insert({
        user_id: candidate.user_id,
        account_id: accountId,
        amount: -Math.abs(amount),
        movement_type: "gasto",
        category: merchantCategory?.category ?? null,
        description: merchantCategory?.name ?? merchant.name,
        occurred_at: occurredAt,
      })
      .select("id")
      .single();
    if (txError) throw txError;
    transactionId = createdTx.id as string;
  }

  const ledgerStatus = reportStatus === "settled" ? "confirmado" : "pendiente";
  await supabase.rpc("award_points", {
    p_user_id: candidate.user_id,
    p_source: "tarjeta",
    p_external_ref: externalRefBase,
    p_points: points,
    p_status: ledgerStatus,
    p_occurred_at: occurredAt,
    p_metadata: { merchant: merchant.name, offer_id: offer.id, transaction_id: transactionId },
  });

  await supabase
    .from("partner_merchant_offers")
    .update({ budget_spent_points: offer.budget_spent_points + points })
    .eq("id", offer.id);

  await markRow(supabase, rowId, {
    match_status: "matched",
    user_id: candidate.user_id,
    linked_card_id: candidate.id,
    merchant_id: merchant.id,
    transaction_id: transactionId,
    points_awarded: points,
    match_note: null,
  });
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

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const provider = resolveProvider(providerName, supabase);
    const records = await provider.fetchPending();

    let processed = 0;
    const errors: string[] = [];

    for (const record of records) {
      try {
        const { data: row, error: upsertError } = await supabase
          .from("card_transactions")
          .upsert(
            {
              provider: providerName === "merchant_report" ? "merchant_report" : providerName,
              provider_transaction_id: record.providerTransactionId,
              merchant_ruc: record.merchantRuc,
              branch: record.branch,
              amount: record.amount,
              occurred_at: record.occurredAt,
              card_last4: record.cardLast4,
              card_brand: record.cardBrand,
              report_status: record.reportStatus,
            },
            { onConflict: "provider,provider_transaction_id" },
          )
          .select()
          .single();
        if (upsertError) throw upsertError;

        if (row.match_status === "pending_match") {
          await reconcileRow(supabase, row);
        }
        processed++;
      } catch (recordError) {
        errors.push(`${record.providerTransactionId}: ${String(recordError)}`);
      }
    }

    return jsonResponse({ provider: providerName, fetched: records.length, processed, errors });
  } catch (error) {
    console.error(error);
    return jsonResponse({ error: String(error) }, 500);
  }
});

// Edge Function: prioritize-payments
//
// EL DIFERENCIADOR DE ALZA: cuando el usuario registra un ingreso, esta
// funcion mira sus cuentas por pagar pendientes y sus recurrentes vencidas,
// y le pide a Claude que arme un plan de pago priorizado — que pagar
// primero, por que, y si el ingreso alcanza para todo. Se llama justo
// despues de guardar un movimiento de tipo "ingreso".
//
// NOTA: no se pudo probar contra un runtime Deno real en este entorno.
//
// Secrets necesarios: ANTHROPIC_API_KEY (el mismo que las otras funciones
// de IA).

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;

interface RankedItem {
  id: string;
  source: "bill" | "recurring" | "debt";
  rank: number;
  reason: string;
}

interface ItemDetails {
  name: string;
  amount: number;
  dueInfo: string;
  accountId: string;
  movementType: string;
  category: string | null;
}

Deno.serve(async (req) => {
  try {
    const { userId, incomeAmount } = await req.json();
    if (!userId || typeof incomeAmount !== "number") {
      return new Response(
        JSON.stringify({ error: "userId and incomeAmount are required" }),
        { status: 400 },
      );
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const [
      { data: bills, error: billsError },
      { data: recurring, error: recurringError },
      { data: accounts, error: accountsError },
      { data: debts, error: debtsError },
    ] = await Promise.all([
      supabase
        .from("bills")
        .select("*")
        .eq("user_id", userId)
        .eq("status", "pendiente")
        .order("due_date", { ascending: true }),
      supabase.from("recurring_transactions").select("*").eq("user_id", userId).eq("active", true),
      supabase.from("accounts").select("*").eq("user_id", userId),
      supabase.from("debts").select("*").eq("user_id", userId).neq("status", "paid_off"),
    ]);

    if (billsError) throw billsError;
    if (recurringError) throw recurringError;
    if (accountsError) throw accountsError;
    if (debtsError) throw debtsError;

    const dueRecurring = (recurring ?? []).filter((item) => isDueOrOverdue(item));
    const activeDebts = debts ?? [];

    if ((bills ?? []).length === 0 && dueRecurring.length === 0 && activeDebts.length === 0) {
      return new Response(JSON.stringify({ hasAdvice: false }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const result = await askClaude(incomeAmount, bills ?? [], dueRecurring, activeDebts, accounts ?? []);

    return new Response(JSON.stringify({ hasAdvice: true, ...result }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error(error);
    return new Response(JSON.stringify({ error: String(error) }), { status: 500 });
  }
});

function isDueOrOverdue(recurringItem: Record<string, unknown>): boolean {
  const today = new Date();
  const dayOfMonth = recurringItem.day_of_month as number;
  const lastLoggedOn = recurringItem.last_logged_on as string | null;

  if (lastLoggedOn) {
    const last = new Date(lastLoggedOn);
    const sameMonth = last.getUTCFullYear() === today.getUTCFullYear() && last.getUTCMonth() === today.getUTCMonth();
    if (sameMonth) return false;
  }

  // Vencida (ya paso su dia este mes) o le toca en los proximos 5 dias.
  const todayDay = today.getUTCDate();
  return todayDay >= dayOfMonth - 5;
}

async function askClaude(
  incomeAmount: number,
  bills: Record<string, unknown>[],
  dueRecurring: Record<string, unknown>[],
  debts: Record<string, unknown>[],
  accounts: Record<string, unknown>[],
): Promise<{ advice: string; items: (RankedItem & ItemDetails)[] }> {
  // Las deudas no tienen cuenta propia (se pagan desde cualquiera), asi que
  // por simplicidad usamos la primera cuenta del usuario como destino del
  // movimiento de "pago de deuda" al marcarla pagada.
  const primaryAccountId = accounts[0]?.id as string | undefined;

  const billsForPrompt = bills.map((b) => ({
    id: b.id,
    source: "bill",
    name: b.name,
    amount: b.amount,
    dueDate: b.due_date,
    category: b.category,
    priority: b.priority,
    accountId: b.account_id,
    movementType: b.movement_type,
  }));
  const recurringForPrompt = dueRecurring.map((r) => ({
    id: r.id,
    source: "recurring",
    name: r.name,
    amount: r.amount,
    dayOfMonth: r.day_of_month,
    category: r.category,
    accountId: r.account_id,
    movementType: r.movement_type,
  }));
  const debtsForPrompt = debts.map((d) => ({
    id: d.id,
    source: "debt",
    name: d.creditor,
    amount: d.minimum_payment ?? d.balance,
    balance: d.balance,
    interestRateMonthly: d.interest_rate_monthly,
    isOverdue: d.is_overdue,
    dueDate: d.due_date,
    accountId: primaryAccountId,
    movementType: "gasto",
  }));

  const prompt = `Eres el asesor financiero de la app Alza. El dueño de un \
negocio acaba de registrar un ingreso de $${incomeAmount.toFixed(2)}. Tiene \
estas cuentas por pagar pendientes, pagos recurrentes vencidos o por vencer \
pronto, y deudas activas (tarjetas de credito, prestamos):

Cuentas por pagar:
${JSON.stringify(billsForPrompt)}

Recurrentes vencidas o por vencer:
${JSON.stringify(recurringForPrompt)}

Deudas activas (el "amount" ya es el pago minimo o el saldo si no hay minimo definido):
${JSON.stringify(debtsForPrompt)}

Saldo actual de sus cuentas:
${JSON.stringify(accounts.map((a) => ({ name: a.name, balance: a.balance, currency: a.currency })))}

Arma un plan de pago priorizado. Considera: que tan vencido/proximo esta \
cada uno, si es un servicio con riesgo de corte (luz, agua, internet), la \
prioridad que el usuario le puso a una cuenta por pagar, si una deuda esta \
en mora o tiene una tasa de interes alta (esas deberian subir de \
prioridad), y si el ingreso alcanza para cubrir todo o hay que elegir.

Responde UNICAMENTE con este JSON (sin texto extra, sin markdown):
{
  "advice": <2-3 oraciones en espanol, tono cercano, con el consejo general>,
  "items": [
    {"id": <id>, "source": "bill"|"recurring"|"debt", "rank": <1, 2, 3...>, "reason": <1 oracion, por que va en ese lugar>}
  ]
}

"items" debe incluir TODOS los que te mande, ordenados del mas urgente al menos urgente.`;

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-sonnet-5-5",
      max_tokens: 1024,
      messages: [{ role: "user", content: prompt }],
    }),
  });

  if (!response.ok) {
    throw new Error(`Anthropic API error: ${response.status} ${await response.text()}`);
  }

  const data = await response.json();
  const text = data.content?.[0]?.text ?? "{}";
  const parsed = JSON.parse(text);

  const byId = new Map<string, ItemDetails>();
  for (const b of billsForPrompt) {
    byId.set(String(b.id), {
      name: b.name as string,
      amount: b.amount as number,
      dueInfo: `Vence ${b.dueDate}`,
      accountId: b.accountId as string,
      movementType: b.movementType as string,
      category: (b.category as string | null) ?? null,
    });
  }
  for (const r of recurringForPrompt) {
    byId.set(String(r.id), {
      name: r.name as string,
      amount: r.amount as number,
      dueInfo: `Dia ${r.dayOfMonth} de cada mes`,
      accountId: r.accountId as string,
      movementType: r.movementType as string,
      category: (r.category as string | null) ?? null,
    });
  }
  for (const d of debtsForPrompt) {
    const overdueText = d.isOverdue ? "En mora. " : "";
    const rateText = d.interestRateMonthly ? `Interes ${d.interestRateMonthly}%/mes.` : "";
    byId.set(String(d.id), {
      name: d.name as string,
      amount: d.amount as number,
      dueInfo: `${overdueText}${rateText}`.trim() || "Deuda activa",
      accountId: (d.accountId as string) ?? "",
      movementType: d.movementType as string,
      category: "Deuda",
    });
  }

  const fallback: ItemDetails = { name: "?", amount: 0, dueInfo: "", accountId: "", movementType: "gasto", category: null };
  const items = ((parsed.items ?? []) as RankedItem[]).map((item) => ({
    ...item,
    ...(byId.get(String(item.id)) ?? fallback),
  }));

  return { advice: parsed.advice ?? "", items };
}

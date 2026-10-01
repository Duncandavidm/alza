// Edge Function: generate-insights
//
// Lee el panorama financiero completo del usuario (perfil, cuentas,
// movimientos recientes, recurrentes y cuentas por pagar), le pide a un LLM
// (Claude, via ANTHROPIC_API_KEY) que genere 2-4 insights financieros, y los
// guarda en public.ai_insights usando la service role key (el usuario nunca
// tiene permiso de insertar ahi directo, ver la migracion 0001_init.sql).
//
// NOTA: no se pudo probar contra un runtime Deno real en este entorno (no
// hay `deno` instalado aqui) — revisar con `supabase functions serve` antes
// de desplegar a produccion.
//
// Secrets necesarios (supabase secrets set ...):
//   ANTHROPIC_API_KEY

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;

interface InsightSuggestion {
  kind: "general" | "spending" | "saving" | "alert";
  title: string;
  body: string;
}

Deno.serve(async (req) => {
  try {
    const { userId } = await req.json();
    if (!userId) {
      return new Response(JSON.stringify({ error: "userId is required" }), { status: 400 });
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const [
      { data: profile, error: profileError },
      { data: accounts, error: accountsError },
      { data: transactions, error: transactionsError },
      { data: recurring, error: recurringError },
      { data: bills, error: billsError },
      { data: debts, error: debtsError },
    ] = await Promise.all([
      supabase.from("profiles").select("*").eq("id", userId).maybeSingle(),
      supabase.from("accounts").select("*").eq("user_id", userId),
      supabase
        .from("transactions")
        .select("*")
        .eq("user_id", userId)
        .order("occurred_at", { ascending: false })
        .limit(50),
      supabase.from("recurring_transactions").select("*").eq("user_id", userId).eq("active", true),
      supabase.from("bills").select("*").eq("user_id", userId).eq("status", "pendiente"),
      supabase.from("debts").select("*").eq("user_id", userId).neq("status", "paid_off"),
    ]);

    if (profileError) throw profileError;
    if (accountsError) throw accountsError;
    if (transactionsError) throw transactionsError;
    if (recurringError) throw recurringError;
    if (billsError) throw billsError;
    if (debtsError) throw debtsError;

    const suggestions = await requestInsightsFromClaude(
      profile,
      accounts ?? [],
      transactions ?? [],
      recurring ?? [],
      bills ?? [],
      debts ?? [],
    );

    if (suggestions.length > 0) {
      const { error: insertError } = await supabase.from("ai_insights").insert(
        suggestions.map((s) => ({
          user_id: userId,
          kind: s.kind,
          title: s.title,
          body: s.body,
        })),
      );
      if (insertError) throw insertError;
    }

    return new Response(JSON.stringify({ inserted: suggestions.length }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error(error);
    return new Response(JSON.stringify({ error: String(error) }), { status: 500 });
  }
});

async function requestInsightsFromClaude(
  profile: Record<string, unknown> | null,
  accounts: Record<string, unknown>[],
  transactions: Record<string, unknown>[],
  recurring: Record<string, unknown>[],
  bills: Record<string, unknown>[],
  debts: Record<string, unknown>[],
): Promise<InsightSuggestion[]> {
  const prompt = `Eres el asesor financiero personal de la app Alza. Con el \
panorama financiero completo de este usuario (perfil — incluye edad, \
estado civil, dependientes, ocupacion, tolerancia al riesgo y metas de \
corto/largo plazo si las dio —, cuentas, ultimos movimientos, \
ingresos/gastos fijos recurrentes, cuentas por pagar pendientes y deudas \
activas, todo en JSON), genera entre 2 y 4 insights financieros cortos, \
accionables y personalizados en espanol — que le ayuden a mejorar su vida \
financiera, no observaciones genericas. Si tiene deudas con interes alto o \
en mora, o si sus metas declaradas chocan con su situacion actual (ej. \
quiere liquidar tarjetas pero sigue acumulando gastos variables altos), \
dilo directamente. Responde UNICAMENTE con un JSON \
array de objetos {"kind": "general"|"spending"|"saving"|"alert", \
"title": string, "body": string}, sin texto extra ni markdown.

Perfil:
${JSON.stringify(profile)}

Cuentas:
${JSON.stringify(accounts)}

Movimientos recientes:
${JSON.stringify(transactions)}

Ingresos y gastos fijos recurrentes:
${JSON.stringify(recurring)}

Cuentas por pagar pendientes:
${JSON.stringify(bills)}

Deudas activas:
${JSON.stringify(debts)}`;

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
  const text = data.content?.[0]?.text ?? "[]";

  try {
    const parsed = JSON.parse(text);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(
      (item): item is InsightSuggestion =>
        typeof item?.title === "string" && typeof item?.body === "string",
    );
  } catch {
    return [];
  }
}

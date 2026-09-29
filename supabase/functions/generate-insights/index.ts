// Edge Function: generate-insights
//
// Lee las cuentas y movimientos recientes de un usuario, le pide a un LLM
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

    const [{ data: accounts, error: accountsError }, { data: transactions, error: transactionsError }] =
      await Promise.all([
        supabase.from("accounts").select("*").eq("user_id", userId),
        supabase
          .from("transactions")
          .select("*")
          .eq("user_id", userId)
          .order("occurred_at", { ascending: false })
          .limit(50),
      ]);

    if (accountsError) throw accountsError;
    if (transactionsError) throw transactionsError;

    const suggestions = await requestInsightsFromClaude(accounts ?? [], transactions ?? []);

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
  accounts: Record<string, unknown>[],
  transactions: Record<string, unknown>[],
): Promise<InsightSuggestion[]> {
  const prompt = `Eres el asesor financiero de la app Alza. Con estos datos del \
usuario (cuentas y sus ultimos movimientos, en JSON), genera entre 2 y 4 \
insights financieros cortos y accionables en espanol. Responde UNICAMENTE \
con un JSON array de objetos {"kind": "general"|"spending"|"saving"|"alert", \
"title": string, "body": string}, sin texto extra ni markdown.

Cuentas:
${JSON.stringify(accounts)}

Movimientos recientes:
${JSON.stringify(transactions)}`;

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

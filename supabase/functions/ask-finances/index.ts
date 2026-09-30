// Edge Function: ask-finances
//
// "Informes con IA": el usuario pregunta algo en lenguaje normal sobre sus
// finanzas ("¿cuanto gaste en comida este mes?") y Claude responde usando
// sus cuentas, movimientos y presupuestos reales como contexto. Inspirado
// en "Pregunta por tus gastos en lenguaje normal y recibe un informe
// completo con los numeros que lo respaldan" de MonAi.
//
// A diferencia de generate-insights (que corre sola y guarda insights
// genericos), esta funcion responde una pregunta puntual del usuario, al
// momento, y no guarda nada en la base.
//
// NOTA: no se pudo probar contra un runtime Deno real en este entorno.
//
// Secrets necesarios: ANTHROPIC_API_KEY (el mismo que usan las otras
// funciones de IA).

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;

Deno.serve(async (req) => {
  try {
    const { userId, question } = await req.json();
    if (!userId || !question) {
      return new Response(
        JSON.stringify({ error: "userId and question are required" }),
        { status: 400 },
      );
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const ninetyDaysAgo = new Date();
    ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90);

    const [
      { data: accounts, error: accountsError },
      { data: transactions, error: transactionsError },
      { data: budgets, error: budgetsError },
    ] = await Promise.all([
      supabase.from("accounts").select("*").eq("user_id", userId),
      supabase
        .from("transactions")
        .select("*")
        .eq("user_id", userId)
        .gte("occurred_at", ninetyDaysAgo.toISOString())
        .order("occurred_at", { ascending: false })
        .limit(300),
      supabase.from("budgets").select("*").eq("user_id", userId),
    ]);

    if (accountsError) throw accountsError;
    if (transactionsError) throw transactionsError;
    if (budgetsError) throw budgetsError;

    const answer = await askClaude(question, accounts ?? [], transactions ?? [], budgets ?? []);

    return new Response(JSON.stringify({ answer }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error(error);
    return new Response(JSON.stringify({ error: String(error) }), { status: 500 });
  }
});

async function askClaude(
  question: string,
  accounts: Record<string, unknown>[],
  transactions: Record<string, unknown>[],
  budgets: Record<string, unknown>[],
): Promise<string> {
  const prompt = `Eres el asesor financiero de la app Alza. El dueño del \
negocio te esta preguntando algo sobre sus finanzas. Respondele en espanol,\
 en lenguaje sencillo (nada de jerga contable), con los numeros exactos que \
respalden tu respuesta. Si la pregunta no se puede responder con estos \
datos, dilo claramente en vez de inventar numeros.

Pregunta: "${question}"

Cuentas:
${JSON.stringify(accounts)}

Movimientos de los ultimos 90 dias (hasta 300):
${JSON.stringify(transactions)}

Presupuestos:
${JSON.stringify(budgets)}

Responde solo con el texto de la respuesta (2-5 oraciones), sin JSON, sin markdown.`;

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-sonnet-5-5",
      max_tokens: 500,
      messages: [{ role: "user", content: prompt }],
    }),
  });

  if (!response.ok) {
    throw new Error(`Anthropic API error: ${response.status} ${await response.text()}`);
  }

  const data = await response.json();
  return data.content?.[0]?.text ?? "No se pudo generar una respuesta.";
}

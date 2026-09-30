// Edge Function: parse-voice-transaction
//
// Recibe la transcripcion de un movimiento dicho en voz alta (ej. "pague
// veinte dolares de gasolina") y le pide a Claude que la convierta en los
// campos que necesita el formulario de "Anotar movimiento": monto,
// descripcion corta, tipo de movimiento y categoria. Inspirado en el
// reconocimiento de voz de MonAi.
//
// No toca la base de datos (no hace falta service role key) — solo
// interpreta texto y regresa JSON. El usuario revisa/edita antes de guardar.
//
// NOTA: no se pudo probar contra un runtime Deno real en este entorno (no
// hay `deno` instalado aqui) — revisar con `supabase functions serve` antes
// de confiar en el.
//
// Secrets necesarios (ya deberian existir si configuraste generate-insights):
//   ANTHROPIC_API_KEY

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;

const MOVEMENT_TYPES = ["ingreso", "gasto", "pago_proveedor", "inversion", "transferencia"] as const;
const CATEGORIES = ["Ingreso", "Vivienda", "Comida", "Transporte", "Entretenimiento", "Salud", "Ahorro", "Otro"];

interface ParsedTransaction {
  amount: number;
  description: string;
  movementType: (typeof MOVEMENT_TYPES)[number];
  category: string | null;
}

Deno.serve(async (req) => {
  try {
    const { transcript } = await req.json();
    if (!transcript || typeof transcript !== "string") {
      return new Response(JSON.stringify({ error: "transcript is required" }), { status: 400 });
    }

    const parsed = await parseWithClaude(transcript);
    if (!parsed) {
      return new Response(
        JSON.stringify({ error: "No se pudo entender el movimiento" }),
        { status: 422 },
      );
    }

    return new Response(JSON.stringify(parsed), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error(error);
    return new Response(JSON.stringify({ error: String(error) }), { status: 500 });
  }
});

async function parseWithClaude(transcript: string): Promise<ParsedTransaction | null> {
  const prompt = `Convierte esta frase dicha en voz alta por el dueño de un \
negocio en un movimiento financiero estructurado. La frase (en espanol o \
espanol mezclado con ingles) describe un ingreso o un gasto del negocio.

Frase: "${transcript}"

Responde UNICAMENTE con un JSON (sin texto extra, sin markdown) con esta forma:
{
  "amount": <numero positivo, el monto en dolares>,
  "description": <descripcion corta, 3-6 palabras, en espanol>,
  "movementType": <uno de: ${MOVEMENT_TYPES.join(", ")}>,
  "category": <uno de: ${CATEGORIES.join(", ")}, o null si no aplica claramente>
}

Reglas:
- Si la frase describe dinero que entra (una venta, un cobro, un pago que te hicieron), movementType es "ingreso".
- Si describe dinero que sale para pagarle a un proveedor de insumos/mercancia, movementType es "pago_proveedor".
- Si describe comprar algo que va a durar (equipo, mejora), movementType es "inversion".
- Si describe mover dinero entre cuentas del negocio, movementType es "transferencia".
- Cualquier otro gasto normal es "gasto".
- Si no se menciona un monto claro, usa 0.`;

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-sonnet-5-5",
      max_tokens: 300,
      messages: [{ role: "user", content: prompt }],
    }),
  });

  if (!response.ok) {
    throw new Error(`Anthropic API error: ${response.status} ${await response.text()}`);
  }

  const data = await response.json();
  const text = data.content?.[0]?.text ?? "";

  try {
    const parsed = JSON.parse(text);
    if (
      typeof parsed.amount !== "number" ||
      typeof parsed.description !== "string" ||
      !MOVEMENT_TYPES.includes(parsed.movementType)
    ) {
      return null;
    }
    return {
      amount: Math.abs(parsed.amount),
      description: parsed.description,
      movementType: parsed.movementType,
      category: CATEGORIES.includes(parsed.category) ? parsed.category : null,
    };
  } catch {
    return null;
  }
}

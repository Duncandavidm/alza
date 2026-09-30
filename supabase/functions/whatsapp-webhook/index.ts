// Edge Function: whatsapp-webhook
//
// Bot de WhatsApp (inspirado en "Escribe al bot de MonAi por WhatsApp, con
// texto o una nota de voz, y aparece en tu lista como transaccion").
//
// Espera el formato de webhook de Twilio para WhatsApp
// (application/x-www-form-urlencoded, campos From/Body/NumMedia/...).
// Ver README para como conectar un numero de Twilio Sandbox for WhatsApp
// (o un numero de WhatsApp Business real) a esta URL.
//
// Flujo:
// 1. El usuario, desde la app (Ajustes > Vincular WhatsApp), genera un
//    codigo y lo guarda en whatsapp_link_codes.
// 2. Le escribe al bot "VINCULAR <codigo>" una vez -> esta funcion vincula
//    su numero de telefono a su cuenta (profiles.whatsapp_number).
// 3. De ahi en adelante, cualquier mensaje de texto se interpreta como un
//    gasto/ingreso (mismo parser que parse-voice-transaction) y se guarda.
//
// LIMITACION DE ESTE MVP: los mensajes de audio (notas de voz) no se
// transcriben aqui — Twilio no transcribe WhatsApp por si solo, hace falta
// contratar un addon o un servicio de STT aparte. Por ahora, si llega un
// mensaje con audio, el bot responde pidiendo que lo manden por texto.
//
// NOTA: no se pudo probar contra un runtime Deno real en este entorno, ni
// contra un numero de Twilio real. Revisar con cuidado antes de conectarlo
// a un numero de produccion.
//
// Secrets necesarios:
//   ANTHROPIC_API_KEY (el mismo que las otras funciones de IA)
//
// verify_jwt debe estar en false para esta funcion (Twilio no manda un JWT
// de Supabase) — se despliega asi desde este repo.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;

const MOVEMENT_TYPES = ["ingreso", "gasto", "pago_proveedor", "inversion", "transferencia"] as const;

Deno.serve(async (req) => {
  try {
    const form = await req.formData();
    const from = String(form.get("From") ?? "").replace("whatsapp:", "").trim();
    const body = String(form.get("Body") ?? "").trim();
    const numMedia = Number(form.get("NumMedia") ?? "0");

    if (!from) {
      return twiml("No pude identificar tu numero.");
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    if (body.toUpperCase().startsWith("VINCULAR")) {
      return await handleLinking(supabase, from, body);
    }

    const { data: profile } = await supabase
      .from("profiles")
      .select("id")
      .eq("whatsapp_number", from)
      .maybeSingle();

    if (!profile) {
      return twiml(
        "Todavia no vinculaste este numero con tu cuenta de Alza. Abre la app > Ajustes > Vincular WhatsApp, y mandame el codigo con 'VINCULAR <codigo>'.",
      );
    }

    if (numMedia > 0) {
      return twiml(
        "Por ahora no puedo escuchar notas de voz por WhatsApp — mandame el gasto por texto, ej. 'Pague 20 de gasolina'.",
      );
    }

    if (!body) {
      return twiml("No entendi el mensaje. Mandame algo como 'Vendi 45 en pasteles'.");
    }

    return await handleTransaction(supabase, profile.id, body);
  } catch (error) {
    console.error(error);
    return twiml("Algo salio mal de mi lado, intenta de nuevo en un rato.");
  }
});

async function handleLinking(
  supabase: ReturnType<typeof createClient>,
  from: string,
  body: string,
): Promise<Response> {
  const code = body.split(/\s+/)[1]?.trim();
  if (!code) {
    return twiml("Manda el codigo asi: 'VINCULAR ABC123'.");
  }

  const { data: linkCode } = await supabase
    .from("whatsapp_link_codes")
    .select("*")
    .eq("code", code)
    .is("used_at", null)
    .maybeSingle();

  if (!linkCode) {
    return twiml("Ese codigo no es valido o ya se uso. Genera uno nuevo desde la app.");
  }

  const { error: updateError } = await supabase
    .from("profiles")
    .update({ whatsapp_number: from })
    .eq("id", linkCode.user_id);

  if (updateError) {
    return twiml("No pude vincular tu numero, intenta de nuevo.");
  }

  await supabase
    .from("whatsapp_link_codes")
    .update({ used_at: new Date().toISOString() })
    .eq("code", code);

  return twiml("Listo, tu WhatsApp ya esta vinculado a Alza. Mandame tus gastos e ingresos cuando quieras.");
}

async function handleTransaction(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  body: string,
): Promise<Response> {
  const { data: accounts } = await supabase
    .from("accounts")
    .select("id")
    .eq("user_id", userId)
    .order("created_at", { ascending: true })
    .limit(1);

  const accountId = accounts?.[0]?.id;
  if (!accountId) {
    return twiml("Crea al menos una cuenta en la app antes de anotar por WhatsApp.");
  }

  const parsed = await parseWithClaude(body);
  if (!parsed) {
    return twiml("No entendi ese movimiento. Intenta algo como 'Pague 20 de gasolina'.");
  }

  const isInflow = parsed.movementType === "ingreso";
  const amount = isInflow ? Math.abs(parsed.amount) : -Math.abs(parsed.amount);

  const { error: insertError } = await supabase.from("transactions").insert({
    user_id: userId,
    account_id: accountId,
    amount,
    movement_type: parsed.movementType,
    category: parsed.category,
    description: parsed.description,
    occurred_at: new Date().toISOString(),
  });

  if (insertError) {
    return twiml("No pude guardar el movimiento, intenta de nuevo.");
  }

  await supabase.rpc("increment_account_balance", { p_account_id: accountId, p_delta: amount });

  return twiml(`Anotado: ${parsed.description} por $${Math.abs(parsed.amount).toFixed(2)}.`);
}

async function parseWithClaude(text: string) {
  const prompt = `Convierte este mensaje de WhatsApp en un movimiento financiero \
estructurado. Responde UNICAMENTE con JSON: {"amount": <numero positivo>, \
"description": <3-6 palabras>, "movementType": <${MOVEMENT_TYPES.join("|")}>, \
"category": <"Ingreso"|"Vivienda"|"Comida"|"Transporte"|"Entretenimiento"|"Salud"|"Ahorro"|"Otro"|null>}.

Mensaje: "${text}"`;

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

  if (!response.ok) return null;

  try {
    const data = await response.json();
    const parsed = JSON.parse(data.content?.[0]?.text ?? "");
    if (typeof parsed.amount !== "number" || !MOVEMENT_TYPES.includes(parsed.movementType)) {
      return null;
    }
    return parsed as { amount: number; description: string; movementType: string; category: string | null };
  } catch {
    return null;
  }
}

function twiml(message: string): Response {
  const escaped = message
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
  return new Response(
    `<?xml version="1.0" encoding="UTF-8"?><Response><Message>${escaped}</Message></Response>`,
    { headers: { "Content-Type": "text/xml" } },
  );
}

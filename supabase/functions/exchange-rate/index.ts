// Edge Function: exchange-rate
//
// Convierte un monto de una moneda a otra usando tasas del Banco Central
// Europeo via frankfurter.app (gratis, sin API key). Inspirado en
// "Paga en otra moneda y MonAi la convierte a la tuya al instante".
//
// Seguridad (ver supabase/functions/README_SECURITY.md):
// - Requiere JWT valido (verify_jwt=true); se decodifica solo para el
//   rate limit.
// - "from"/"to" validados como codigos de moneda ISO 4217 (3 letras).
// - "amount" validado: numero finito, positivo, tope razonable.
// - Rate limit: 60 llamadas / 10 minutos por usuario.
// - CORS sin Access-Control-Allow-Origin (solo la app nativa la llama).
//
// NOTA: no se pudo probar contra un runtime Deno real en este entorno.
//
// No necesita secrets de terceros (frankfurter.app es publico y sin
// key); SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY los inyecta Supabase solo.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS_HEADERS = {
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

function getVerifiedUserId(req: Request): string | null {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return null;
  const parts = authHeader.slice(7).split(".");
  if (parts.length !== 3) return null;
  try {
    const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
    return typeof payload.sub === "string" ? payload.sub : null;
  } catch {
    return null;
  }
}

async function checkRateLimit(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  functionName: string,
  maxRequests: number,
  windowSeconds: number,
): Promise<boolean> {
  const { data, error } = await supabase.rpc("check_and_increment_rate_limit", {
    p_user_id: userId,
    p_function_name: functionName,
    p_max_requests: maxRequests,
    p_window_seconds: windowSeconds,
  });
  if (error) {
    console.error("rate limit check failed", error);
    return true;
  }
  return data === true;
}

interface ExchangeRateResponse {
  amount: number;
  base: string;
  date: string;
  rates: Record<string, number>;
}

const CURRENCY_CODE_PATTERN = /^[A-Z]{3}$/;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  try {
    const userId = getVerifiedUserId(req);
    if (!userId) {
      return jsonResponse({ error: "No autorizado" }, 401);
    }

    const body = await req.json();
    const from = typeof body?.from === "string" ? body.from.toUpperCase() : "";
    const to = typeof body?.to === "string" ? body.to.toUpperCase() : "";
    const amount = body?.amount;

    if (!CURRENCY_CODE_PATTERN.test(from) || !CURRENCY_CODE_PATTERN.test(to)) {
      return jsonResponse({ error: "from y to deben ser codigos de moneda de 3 letras" }, 400);
    }
    if (typeof amount !== "number" || !Number.isFinite(amount) || amount <= 0 || amount > 1_000_000_000) {
      return jsonResponse({ error: "amount invalido" }, 400);
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const allowed = await checkRateLimit(supabase, userId, "exchange-rate", 60, 600);
    if (!allowed) {
      return jsonResponse({ error: "Demasiadas solicitudes, intenta en unos minutos." }, 429);
    }

    if (from === to) {
      return jsonResponse({ rate: 1, convertedAmount: amount });
    }

    const response = await fetch(
      `https://api.frankfurter.app/latest?amount=${amount}&from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`,
    );

    if (!response.ok) {
      throw new Error(`frankfurter.app error: ${response.status} ${await response.text()}`);
    }

    const data: ExchangeRateResponse = await response.json();
    const convertedAmount = data.rates[to];

    if (typeof convertedAmount !== "number") {
      return jsonResponse({ error: `No hay tasa disponible para ${from} -> ${to}` }, 422);
    }

    return jsonResponse({
      rate: convertedAmount / amount,
      convertedAmount,
    });
  } catch (error) {
    console.error(error);
    return jsonResponse({ error: String(error) }, 500);
  }
});

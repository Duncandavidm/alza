// Modulo comun de IA para las Edge Functions de MonAvi (se copia como
// ai.ts dentro de cada funcion que lo usa al desplegar).
//
// - Modelo: Claude Opus 5.5 con esfuerzo alto (calidad maxima).
// - Antes de cada llamada: cuota de la persona + tope diario global
//   (ai_guard, migracion 0050). Despues: tokens y costo (ai_record_usage).
// - Respaldo del lado del servidor si el modelo rechaza (fallbacks).

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;
export const AI_MODEL = "claude-opus-5-5";

// USD por millon de tokens (input, output, cache read, cache write 5 min).
const PRICES: Record<string, [number, number, number, number]> = {
  "claude-opus-5-5": [4, 20, 0.2, 5],
  "claude-opus-5": [5, 25, 0.5, 6.25],
  "claude-opus-4-8": [5, 25, 0.5, 6.25],
  "claude-sonnet-5-5": [2, 10, 0.1, 2.5],
  "claude-sonnet-5": [2, 10, 0.2, 2.5],
};

export class AiLimitError extends Error {
  constructor(public code: "ai_quota" | "ai_budget", message: string) {
    super(message);
  }
}

interface Guard {
  allowed: boolean;
  reason?: "quota" | "budget";
  used?: number;
  limit?: number;
  period?: string;
  resets_at?: string;
}

const MONTHS = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];

const NOUN: Record<string, string> = {
  "parse-voice-transaction": "notas por voz",
  "ask-finances": "preguntas",
  "generate-insights": "análisis de hoy",
  "prioritize-payments": "planes de pago con IA de hoy",
};

function limitMessage(fn: string, guard: Guard): string {
  if (guard.reason === "budget") {
    return "Las funciones de IA están en pausa por hoy por alta demanda. Vuelven mañana. Puedes seguir anotando a mano.";
  }
  const noun = NOUN[fn] ?? "usos de IA";
  if (guard.period === "day") {
    return `Ya usaste tus ${noun}. Se renueva mañana.`;
  }
  const reset = guard.resets_at ? new Date(guard.resets_at) : null;
  // resets_at es medianoche de Panama (05:00 UTC): el dia en Panama.
  const when = reset
    ? `el ${new Date(reset.getTime() - 5 * 3600_000).getUTCDate()} de ${MONTHS[new Date(reset.getTime() - 5 * 3600_000).getUTCMonth()]}`
    : "el próximo mes";
  return `Usaste tus ${guard.limit} ${noun} de este mes. Se renuevan ${when}.`;
}

/// Lanza AiLimitError si la persona no tiene cuota o se alcanzo el tope.
export async function ensureAiAllowed(supabase: SupabaseClient, userId: string, fn: string): Promise<Guard> {
  const { data, error } = await supabase.rpc("ai_guard", { p_user_id: userId, p_function: fn });
  if (error) {
    // Si el control falla, no se bloquea a la persona (se registra el error).
    console.error("ai_guard", error.message);
    return { allowed: true };
  }
  const guard = data as Guard;
  if (!guard.allowed) {
    if (guard.reason === "budget") console.error("AI: tope diario alcanzado, funciones de IA en pausa");
    throw new AiLimitError(guard.reason === "budget" ? "ai_budget" : "ai_quota", limitMessage(fn, guard));
  }
  return guard;
}

/// Registra un resultado guardado (no llamo a Claude, no cuenta en cuota).
export async function recordCachedHit(supabase: SupabaseClient, userId: string, fn: string) {
  await supabase.rpc("ai_record_usage", {
    p_user_id: userId, p_function: fn, p_model: "cache", p_input: 0, p_output: 0,
    p_cache_read: 0, p_cache_write: 0, p_cost: 0, p_cached: true,
  });
}

export interface ClaudeResult {
  text: string;
  stopReason: string | null;
  model: string;
}

/// Llama a Claude, registra tokens y costo, y devuelve el texto final
/// (sin los bloques de razonamiento). Lanza si la API falla o rechaza.
export async function callClaude(
  supabase: SupabaseClient,
  userId: string,
  fn: string,
  opts: { system?: string; prompt: string; maxTokens: number },
): Promise<ClaudeResult> {
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "anthropic-beta": "server-side-fallback-2026-07-01",
    },
    body: JSON.stringify({
      model: AI_MODEL,
      max_tokens: opts.maxTokens,
      output_config: { effort: "high" },
      fallbacks: "default",
      ...(opts.system ? { system: opts.system } : {}),
      messages: [{ role: "user", content: opts.prompt }],
    }),
    signal: AbortSignal.timeout(120_000),
  });

  if (!response.ok) {
    throw new Error(`Anthropic API error: ${response.status} ${await response.text()}`);
  }
  const data = await response.json();

  const usage = data.usage ?? {};
  const model = typeof data.model === "string" ? data.model : AI_MODEL;
  const [pin, pout, pread, pwrite] = PRICES[model] ?? PRICES[AI_MODEL];
  const input = Number(usage.input_tokens ?? 0);
  const output = Number(usage.output_tokens ?? 0);
  const cacheRead = Number(usage.cache_read_input_tokens ?? 0);
  const cacheWrite = Number(usage.cache_creation_input_tokens ?? 0);
  const cost = (input * pin + output * pout + cacheRead * pread + cacheWrite * pwrite) / 1_000_000;
  const { error: usageError } = await supabase.rpc("ai_record_usage", {
    p_user_id: userId, p_function: fn, p_model: model, p_input: input, p_output: output,
    p_cache_read: cacheRead, p_cache_write: cacheWrite, p_cost: cost, p_cached: false,
  });
  if (usageError) console.error("ai_record_usage", usageError.message);

  if (data.stop_reason === "refusal") {
    throw new Error("Claude rechazo la solicitud (refusal)");
  }
  const blocks: { type?: string; text?: string }[] = Array.isArray(data.content) ? data.content : [];
  const text = blocks.filter((b) => b?.type === "text" && typeof b.text === "string").map((b) => b.text).join("\n").trim();
  return { text, stopReason: data.stop_reason ?? null, model };
}

/// Extrae el primer JSON ({...} o [...]) del texto.
export function extractJsonFromText(text: string, open: "[" | "{"): unknown {
  const close = open === "[" ? "]" : "}";
  const start = text.indexOf(open);
  const end = text.lastIndexOf(close);
  if (start === -1 || end <= start) throw new Error("La respuesta de Claude no trae JSON");
  return JSON.parse(text.slice(start, end + 1));
}

/// Respuesta HTTP para cuota/tope alcanzado (la app muestra `error`).
export function limitResponse(error: AiLimitError, headers: Record<string, string>): Response {
  return new Response(JSON.stringify({ error: error.message, code: error.code }), {
    status: 429,
    headers: { "Content-Type": "application/json", ...headers },
  });
}

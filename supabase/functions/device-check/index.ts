// Edge Function: device-check (1.1.0)
//
// DeviceCheck de Apple: dos bits por iPhone guardados en Apple que
// sobreviven a borrar el iPhone de fábrica (ver migración 0103).
// La app manda {device_token, device_id} una vez al día. La función lee los
// bits en Apple, deja que device_check_record decida (y abra una revisión
// de cashback si hace falta) y escribe en Apple los bits nuevos.
//
// Secrets (Supabase → Edge Functions → Secrets). Mientras falten, la
// función responde {configured:false} y no hace nada:
//   DEVICECHECK_KEY_ID       id de la clave con DeviceCheck activado
//   DEVICECHECK_PRIVATE_KEY  contenido del .p8 (con -----BEGIN PRIVATE KEY-----)
//   APNS_TEAM_ID             Team ID de Apple Developer (ya existe)
//   DEVICECHECK_ENVIRONMENT  opcional: "development" para forzar el entorno
//                            de desarrollo; si no, se prueba producción y,
//                            si Apple rechaza el token, desarrollo (builds
//                            instalados desde Xcode).
//
// Seguridad: verify_jwt; la cuenta sale del JWT. Apple solo recibe el token
// del iPhone y los dos bits, nada de la persona.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const KEY_ID = Deno.env.get("DEVICECHECK_KEY_ID")?.trim();
const PRIVATE_KEY = Deno.env.get("DEVICECHECK_PRIVATE_KEY");
const TEAM_ID = (Deno.env.get("DEVICECHECK_TEAM_ID") ?? Deno.env.get("APNS_TEAM_ID"))?.trim();
const FORCED_ENVIRONMENT = Deno.env.get("DEVICECHECK_ENVIRONMENT")?.trim();

const PRODUCTION = "https://api.devicecheck.apple.com/v1";
const DEVELOPMENT = "https://api.development.devicecheck.apple.com/v1";

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function getVerifiedUserId(req: Request): string | null {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return null;
  const parts = authHeader.slice(7).split(".");
  if (parts.length !== 3) return null;
  try {
    const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
    return typeof payload.sub === "string" && payload.role === "authenticated" ? payload.sub : null;
  } catch {
    return null;
  }
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

let cachedToken: { value: string; createdAt: number } | null = null;

async function appleToken(): Promise<string> {
  if (cachedToken && Date.now() - cachedToken.createdAt < 40 * 60 * 1000) return cachedToken.value;
  const pem = (PRIVATE_KEY ?? "")
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (char) => char.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const signingInput = `${base64UrlJson({ alg: "ES256", kid: KEY_ID })}.${base64UrlJson({ iss: TEAM_ID, iat: Math.floor(Date.now() / 1000) })}`;
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput)),
  );
  cachedToken = { value: `${signingInput}.${base64Url(signature)}`, createdAt: Date.now() };
  return cachedToken.value;
}

async function callApple(base: string, path: string, body: Record<string, unknown>): Promise<Response> {
  return await fetch(`${base}/${path}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${await appleToken()}`, "Content-Type": "application/json" },
    body: JSON.stringify({ ...body, transaction_id: crypto.randomUUID(), timestamp: Date.now() }),
  });
}

interface Bits {
  bit0: boolean;
  bit1: boolean;
  lastUpdate: string | null;
}

/** Lee los bits. Devuelve también el entorno que aceptó el token. */
async function queryBits(deviceToken: string): Promise<{ base: string; bits: Bits }> {
  const bases = FORCED_ENVIRONMENT === "development" ? [DEVELOPMENT] : [PRODUCTION, DEVELOPMENT];
  let lastError = "";
  for (const base of bases) {
    const response = await callApple(base, "query_two_bits", { device_token: deviceToken });
    const text = await response.text();
    if (response.ok) {
      // Sin bits guardados todavía, Apple responde 200 con texto plano.
      if (!text.trim().startsWith("{")) return { base, bits: { bit0: false, bit1: false, lastUpdate: null } };
      const json = JSON.parse(text);
      return {
        base,
        bits: { bit0: json.bit0 === true, bit1: json.bit1 === true, lastUpdate: typeof json.last_update_time === "string" ? json.last_update_time : null },
      };
    }
    lastError = `${response.status} ${text.slice(0, 120)}`;
    // 400 = token de otro entorno (o mal formado): probar el siguiente.
    if (response.status !== 400) break;
  }
  throw new Error(`DeviceCheck query: ${lastError}`);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return jsonResponse({ error: "Método no permitido" }, 405);

  const userId = getVerifiedUserId(req);
  if (!userId) return jsonResponse({ error: "No autorizado" }, 401);

  if (!KEY_ID || !PRIVATE_KEY || !TEAM_ID) return jsonResponse({ configured: false });

  let body: { device_token?: unknown; device_id?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "JSON inválido" }, 400);
  }
  const deviceToken = body.device_token;
  const deviceId = body.device_id;
  if (typeof deviceToken !== "string" || deviceToken.length < 20 || deviceToken.length > 10000) {
    return jsonResponse({ error: "device_token inválido" }, 400);
  }
  if (typeof deviceId !== "string" || deviceId.length < 16 || deviceId.length > 80) {
    return jsonResponse({ error: "device_id inválido" }, 400);
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: allowed } = await supabase.rpc("check_and_increment_rate_limit", {
    p_user_id: userId,
    p_function_name: "device-check",
    p_max_requests: 6,
    p_window_seconds: 86400,
  });
  if (allowed === false) return jsonResponse({ error: "Demasiadas solicitudes" }, 429);

  try {
    const { base, bits } = await queryBits(deviceToken);

    const { data: desired, error } = await supabase.rpc("device_check_record", {
      p_user: userId,
      p_device_id: deviceId,
      p_bit0: bits.bit0,
      p_bit1: bits.bit1,
      p_last_update: bits.lastUpdate,
    });
    if (error) throw error;

    const want = desired as { bit0: boolean; bit1: boolean };
    if (want.bit0 !== bits.bit0 || want.bit1 !== bits.bit1) {
      const response = await callApple(base, "update_two_bits", { device_token: deviceToken, bit0: want.bit0, bit1: want.bit1 });
      if (!response.ok) console.error("device-check update", response.status, (await response.text()).slice(0, 120));
    }
    return jsonResponse({ configured: true, ok: true });
  } catch (error) {
    console.error("device-check", String(error));
    return jsonResponse({ error: "temporal" }, 502);
  }
});

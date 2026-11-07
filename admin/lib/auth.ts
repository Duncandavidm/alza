// Autenticacion minima para este panel interno: una sola clave
// compartida (ADMIN_PANEL_PASSWORD) y una cookie firmada con HMAC
// (SESSION_SECRET) — sin usuarios individuales, sin Supabase Auth,
// porque el alcance pedido es "panel admin minimo" para un solo
// operador (o un equipo chico que comparte la clave).
//
// Web Crypto (no el modulo `crypto` de Node) para que funcione igual
// en Node y en Edge runtime, por si el middleware corre en cualquiera
// de los dos.

export const SESSION_COOKIE_NAME = "monavi_admin_session";
const SESSION_TTL_MS = 1000 * 60 * 60 * 12; // 12 horas
export const SESSION_MAX_AGE_SECONDS = SESSION_TTL_MS / 1000;

function getSessionSecret(): string {
  const secret = process.env.SESSION_SECRET;
  if (!secret) throw new Error("Falta la variable de entorno SESSION_SECRET");
  return secret;
}

async function hmac(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Buffer.from(signature).toString("base64url");
}

export async function createSessionToken(): Promise<string> {
  const expiresAt = Date.now() + SESSION_TTL_MS;
  const payload = String(expiresAt);
  const signature = await hmac(getSessionSecret(), payload);
  return `${payload}.${signature}`;
}

export async function isValidSessionToken(token: string | undefined): Promise<boolean> {
  if (!token) return false;
  const [payload, signature] = token.split(".");
  if (!payload || !signature) return false;

  const expiresAt = Number(payload);
  if (!Number.isFinite(expiresAt) || expiresAt < Date.now()) return false;

  const expectedSignature = await hmac(getSessionSecret(), payload);
  return expectedSignature === signature;
}

export function checkAdminPassword(candidate: string): boolean {
  const expected = process.env.ADMIN_PANEL_PASSWORD;
  if (!expected) throw new Error("Falta la variable de entorno ADMIN_PANEL_PASSWORD");
  // Se ignoran espacios y saltos de linea al inicio y al final: al pegar la
  // clave en Vercel (o en el formulario) es facil que se cuele uno y la
  // clave "correcta" nunca coincida.
  return constantTimeEqual(candidate.trim(), expected.trim());
}

/// Compara sin cortar en la primera diferencia, para no dar pistas por
/// tiempo de respuesta a quien intente adivinar la clave.
function constantTimeEqual(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  let diff = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let i = 0; i < length; i++) {
    diff |= (left[i] ?? 0) ^ (right[i] ?? 0);
  }
  return diff === 0;
}

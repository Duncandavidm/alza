import "server-only";
import { createHmac, timingSafeEqual } from "node:crypto";

// "Turno" de caja en /canjear: despues del primer PIN correcto se guarda
// una cookie httpOnly firmada (HMAC-SHA256) con el comercio y un
// vencimiento de 12 horas. Mientras sea valida el cajero solo escanea
// (RPC merchant_redeem_session, que exige que el codigo sea de ese
// comercio). La firma usa ADMIN_JOB_SECRET (secreto solo del servidor)
// con un prefijo propio para que el token no sirva para nada mas.

export const REDEEM_SESSION_COOKIE = "monavi_caja";
export const REDEEM_SESSION_TTL_SECONDS = 60 * 60 * 12;
const TOKEN_CONTEXT = "monavi-canjear-turno:v1";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type RedeemSession = { merchant_id: string; exp: number };

function secret(): string {
  const value = process.env.ADMIN_JOB_SECRET;
  if (!value) throw new Error("Falta la variable de entorno ADMIN_JOB_SECRET");
  return value;
}

function sign(payload: string): Buffer {
  return createHmac("sha256", secret()).update(`${TOKEN_CONTEXT}.${payload}`).digest();
}

export function createRedeemSessionToken(merchantId: string): string {
  const session: RedeemSession = {
    merchant_id: merchantId,
    exp: Math.floor(Date.now() / 1000) + REDEEM_SESSION_TTL_SECONDS,
  };
  const payload = Buffer.from(JSON.stringify(session)).toString("base64url");
  return `${payload}.${sign(payload).toString("base64url")}`;
}

/// Devuelve la sesion si la firma es valida (comparacion en tiempo
/// constante) y no vencio; si no, null.
export function readRedeemSessionToken(token: string | undefined | null): RedeemSession | null {
  if (!token || token.length > 1000) return null;
  const [payload, signature, extra] = token.split(".");
  if (!payload || !signature || extra !== undefined) return null;
  try {
    const expected = sign(payload);
    const given = Buffer.from(signature, "base64url");
    if (given.length !== expected.length || !timingSafeEqual(given, expected)) return null;
    const session = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as Partial<RedeemSession>;
    if (typeof session.merchant_id !== "string" || !UUID_RE.test(session.merchant_id)) return null;
    if (typeof session.exp !== "number" || session.exp * 1000 <= Date.now()) return null;
    return { merchant_id: session.merchant_id, exp: session.exp };
  } catch {
    return null;
  }
}

export const REDEEM_SESSION_COOKIE_OPTIONS = {
  httpOnly: true,
  secure: true,
  sameSite: "strict" as const,
  path: "/canjear",
  maxAge: REDEEM_SESSION_TTL_SECONDS,
};

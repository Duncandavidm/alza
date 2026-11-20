"use server";

import { createHash } from "node:crypto";
import { cookies, headers } from "next/headers";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { formatDateTime } from "@/lib/format";
import { formatRewardValueLong, toRewardCurrency } from "@/lib/currency";
import {
  REDEEM_SESSION_COOKIE,
  REDEEM_SESSION_COOKIE_OPTIONS,
  createRedeemSessionToken,
  readRedeemSessionToken,
} from "@/lib/redeem-session";

export type RedeemResult =
  | {
      ok: true;
      delivered: boolean;
      code: string;
      product: string;
      photoUrl: string | null;
      merchant: string;
      isGift: boolean;
      valueLabel: string;
      expiresLabel: string;
      deliveredLabel: string | null;
      /// Comercio del turno abierto (si quedo una sesion activa).
      session: { merchant: string } | null;
    }
  | {
      ok: false;
      error: string;
      product?: string;
      needsPin?: boolean;
      /// Se esperaba un turno abierto (sin PIN) y la cookie ya no es valida.
      sessionExpired?: boolean;
      session?: { merchant: string } | null;
    };

type RpcResponse = {
  ok?: boolean;
  error?: string;
  delivered?: boolean;
  code?: string;
  product?: string | null;
  photo_url?: string | null;
  merchant?: string | null;
  merchant_id?: string | null;
  is_gift?: boolean | null;
  value_cents?: number | null;
  currency?: string | null;
  value?: number | null;
  expires_at?: string | null;
  delivered_at?: string | null;
};

/// IP del cliente -> hash SHA-256 con SESSION_SECRET. Nunca se guarda ni
/// se envia la IP en claro: las RPC solo la usan para limitar los
/// intentos fallidos (10 cada 15 minutos).
async function clientIpHash(): Promise<string> {
  const list = await headers();
  const forwarded = list.get("x-forwarded-for")?.split(",")[0]?.trim();
  const ip = forwarded || list.get("x-real-ip")?.trim() || "desconocida";
  const secret = process.env.SESSION_SECRET;
  if (!secret) throw new Error("Falta la variable de entorno SESSION_SECRET");
  return createHash("sha256").update(`${secret}:${ip}`).digest("hex");
}

/// Sesion de turno vigente (cookie firmada) o null.
async function currentSession() {
  const store = await cookies();
  return readRedeemSessionToken(store.get(REDEEM_SESSION_COOKIE)?.value);
}

// Accion PUBLICA (sin sesion del panel): /canjear esta en PUBLIC_PATHS de
// proxy.ts. Con un turno abierto se valida sin PIN (merchant_redeem_session,
// solo codigos de ese comercio); si no, con PIN (merchant_redeem). Toda la
// verificacion la hacen las RPC con service role.
export async function redeemCode(input: {
  code: string;
  pin?: string;
  confirm: boolean;
  /// true desde la app con turno: si la cookie vencio no se pide PIN aqui,
  /// se avisa para volver a "Iniciar turno".
  requireSession?: boolean;
}): Promise<RedeemResult> {
  const code = String(input?.code ?? "")
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .slice(0, 12);
  const pin = String(input?.pin ?? "").trim();
  if (code.length !== 6) return { ok: false, error: "El código tiene 6 letras y números." };

  try {
    const session = await currentSession();
    const ipHash = await clientIpHash();
    let data: unknown;
    let rpcError: { message: string } | null;

    if (session) {
      ({ data, error: rpcError } = await supabaseAdmin().rpc("merchant_redeem_session", {
        p_code: code,
        p_merchant_id: session.merchant_id,
        p_ip_hash: ipHash,
        p_confirm: input.confirm === true,
      }));
    } else {
      if (input.requireSession) {
        return { ok: false, error: "Tu turno terminó. Inicia turno de nuevo.", sessionExpired: true };
      }
      if (!/^\d{6}$/.test(pin)) return { ok: false, error: "Escribe el PIN de 6 dígitos del comercio.", needsPin: true };
      ({ data, error: rpcError } = await supabaseAdmin().rpc("merchant_redeem", {
        p_code: code,
        p_pin: pin,
        p_ip_hash: ipHash,
        p_confirm: input.confirm === true,
      }));
    }
    if (rpcError) {
      console.error("canjear rpc", rpcError.message);
      return { ok: false, error: "No se pudo validar el código. Intenta de nuevo en un momento." };
    }

    const result = (data ?? {}) as RpcResponse;
    if (!result.ok) {
      return {
        ok: false,
        error: result.error || "No se pudo validar el código.",
        product: result.product ?? undefined,
        needsPin: !session,
      };
    }

    // Primer PIN correcto del turno: se abre la sesion de 12 horas.
    let sessionInfo: { merchant: string } | null = session ? { merchant: result.merchant ?? "" } : null;
    if (!session && result.merchant_id) {
      const store = await cookies();
      store.set(REDEEM_SESSION_COOKIE, createRedeemSessionToken(result.merchant_id), REDEEM_SESSION_COOKIE_OPTIONS);
      sessionInfo = { merchant: result.merchant ?? "" };
    }

    return {
      ok: true,
      delivered: result.delivered === true,
      code: result.code ?? code,
      product: result.product ?? "Producto",
      photoUrl: result.photo_url ?? null,
      merchant: result.merchant ?? "",
      isGift: result.is_gift === true,
      // "$3.50 de cashback" o "150 puntos". Si la RPC no trae currency/value
      // (version anterior), se asume cashback en centavos (value_cents).
      valueLabel: result.currency
        ? formatRewardValueLong(Number(result.value ?? result.value_cents ?? 0), toRewardCurrency(result.currency))
        : formatRewardValueLong(Number(result.value_cents ?? 0), "cashback"),
      expiresLabel: formatDateTime(result.expires_at),
      deliveredLabel: result.delivered_at ? formatDateTime(result.delivered_at) : null,
      session: sessionInfo,
    };
  } catch (error) {
    console.error("canjear", error instanceof Error ? error.message : error);
    return { ok: false, error: "No se pudo validar el código. Revisa tu conexión e intenta de nuevo." };
  }
}

/// Respuesta de merchant_login.
type LoginRpcResponse = {
  ok?: boolean;
  error?: string;
  merchant_id?: string | null;
  merchant?: string | { name?: string | null } | null;
};

export type StartShiftResult = { ok: true; merchant: string } | { ok: false; error: string };

/// "Iniciar turno": RUC + PIN del comercio (merchant_login). Si es correcto
/// se abre la cookie firmada de 12 horas.
export async function startShift(input: { ruc: string; pin: string }): Promise<StartShiftResult> {
  const ruc = String(input?.ruc ?? "").trim().slice(0, 40);
  const pin = String(input?.pin ?? "").trim();
  if (ruc.length < 3) return { ok: false, error: "Escribe el RUC del comercio." };
  if (!/^\d{6}$/.test(pin)) return { ok: false, error: "El PIN tiene 6 dígitos." };

  try {
    const { data, error } = await supabaseAdmin().rpc("merchant_login", {
      p_ruc: ruc,
      p_pin: pin,
      p_ip_hash: await clientIpHash(),
    });
    if (error) {
      console.error("canjear login rpc", error.message);
      return { ok: false, error: "No se pudo iniciar el turno. Intenta de nuevo en un momento." };
    }
    const result = (data ?? {}) as LoginRpcResponse;
    if (!result.ok || !result.merchant_id) {
      return { ok: false, error: result.error || "RUC o PIN incorrectos." };
    }
    const merchant =
      typeof result.merchant === "string" ? result.merchant : (result.merchant?.name ?? "");
    const store = await cookies();
    store.set(REDEEM_SESSION_COOKIE, createRedeemSessionToken(result.merchant_id), REDEEM_SESSION_COOKIE_OPTIONS);
    return { ok: true, merchant: merchant || "tu comercio" };
  } catch (error) {
    console.error("canjear login", error instanceof Error ? error.message : error);
    return { ok: false, error: "No se pudo iniciar el turno. Revisa tu conexión e intenta de nuevo." };
  }
}

export type PendingRedemption = {
  code: string;
  product: string;
  photoUrl: string | null;
  isGift: boolean;
  expiresLabel: string;
  customer: string;
  phoneHint: string | null;
};

export type SearchPendingResult =
  | { ok: true; items: PendingRedemption[] }
  | { ok: false; error: string; sessionExpired?: boolean };

type PendingRow = {
  code?: string | null;
  product?: string | null;
  photo_url?: string | null;
  is_gift?: boolean | null;
  expires_at?: string | null;
  customer?: string | null;
  phone_hint?: string | null;
};

/// "Buscar cliente": canjes pendientes del comercio del turno
/// (merchant_pending_redemptions). Consulta vacia = todos los pendientes.
export async function searchPending(input: { query: string }): Promise<SearchPendingResult> {
  const query = String(input?.query ?? "").trim().slice(0, 80);
  try {
    const session = await currentSession();
    if (!session) return { ok: false, error: "Tu turno terminó. Inicia turno de nuevo.", sessionExpired: true };
    const { data, error } = await supabaseAdmin().rpc("merchant_pending_redemptions", {
      p_merchant_id: session.merchant_id,
      p_query: query,
    });
    if (error) {
      console.error("canjear pendientes rpc", error.message);
      return { ok: false, error: "No se pudo buscar. Intenta de nuevo en un momento." };
    }
    const rows = (Array.isArray(data) ? data : []) as PendingRow[];
    return {
      ok: true,
      items: rows
        .filter((row) => typeof row.code === "string" && row.code)
        .slice(0, 100)
        .map((row) => ({
          code: String(row.code),
          product: row.product ?? "Producto",
          photoUrl: row.photo_url ?? null,
          isGift: row.is_gift === true,
          expiresLabel: formatDateTime(row.expires_at),
          customer: row.customer ?? "Cliente",
          phoneHint: row.phone_hint ?? null,
        })),
    };
  } catch (error) {
    console.error("canjear pendientes", error instanceof Error ? error.message : error);
    return { ok: false, error: "No se pudo buscar. Revisa tu conexión e intenta de nuevo." };
  }
}

/// "Cerrar turno": borra la cookie; el proximo canje vuelve a pedir PIN.
export async function endShift(): Promise<void> {
  const store = await cookies();
  store.set(REDEEM_SESSION_COOKIE, "", { ...REDEEM_SESSION_COOKIE_OPTIONS, maxAge: 0 });
}

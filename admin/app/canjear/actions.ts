"use server";

import { createHash } from "node:crypto";
import { headers } from "next/headers";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { formatDateTime } from "@/lib/format";
import { formatRewardValueLong, toRewardCurrency } from "@/lib/currency";

export type RedeemResult =
  | {
      ok: true;
      delivered: boolean;
      code: string;
      product: string;
      photoUrl: string | null;
      merchant: string;
      valueLabel: string;
      expiresLabel: string;
      deliveredLabel: string | null;
    }
  | { ok: false; error: string; product?: string };

type RpcResponse = {
  ok?: boolean;
  error?: string;
  delivered?: boolean;
  code?: string;
  product?: string | null;
  photo_url?: string | null;
  merchant?: string | null;
  value_cents?: number | null;
  currency?: string | null;
  value?: number | null;
  expires_at?: string | null;
  delivered_at?: string | null;
};

/// IP del cliente -> hash SHA-256 con SESSION_SECRET. Nunca se guarda ni
/// se envia la IP en claro: merchant_redeem() solo la usa para limitar
/// los intentos fallidos (10 cada 15 minutos).
async function clientIpHash(): Promise<string> {
  const list = await headers();
  const forwarded = list.get("x-forwarded-for")?.split(",")[0]?.trim();
  const ip = forwarded || list.get("x-real-ip")?.trim() || "desconocida";
  const secret = process.env.SESSION_SECRET;
  if (!secret) throw new Error("Falta la variable de entorno SESSION_SECRET");
  return createHash("sha256").update(`${secret}:${ip}`).digest("hex");
}

// Accion PUBLICA (sin sesion): /canjear esta en PUBLIC_PATHS de proxy.ts.
// Toda la verificacion (codigo del comercio correcto, PIN bcrypt, vigencia,
// limite de intentos) la hace la RPC merchant_redeem con service role; aqui
// solo se normaliza la entrada y se devuelve lo minimo para la pantalla.
export async function redeemCode(input: { code: string; pin: string; confirm: boolean }): Promise<RedeemResult> {
  const code = String(input?.code ?? "")
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .slice(0, 12);
  const pin = String(input?.pin ?? "").trim();

  if (code.length !== 6) return { ok: false, error: "El código tiene 6 letras y números." };
  if (!/^\d{6}$/.test(pin)) return { ok: false, error: "El PIN tiene 6 dígitos." };

  try {
    const { data, error } = await supabaseAdmin().rpc("merchant_redeem", {
      p_code: code,
      p_pin: pin,
      p_ip_hash: await clientIpHash(),
      p_confirm: input.confirm === true,
    });
    if (error) {
      console.error("merchant_redeem", error.message);
      return { ok: false, error: "No se pudo validar el código. Intenta de nuevo en un momento." };
    }

    const result = (data ?? {}) as RpcResponse;
    if (!result.ok) {
      return {
        ok: false,
        error: result.error || "No se pudo validar el código.",
        product: result.product ?? undefined,
      };
    }

    return {
      ok: true,
      delivered: result.delivered === true,
      code: result.code ?? code,
      product: result.product ?? "Producto",
      photoUrl: result.photo_url ?? null,
      merchant: result.merchant ?? "",
      // "$3.50 de cashback" o "150 puntos". Si la RPC no trae currency/value
      // (version anterior), se asume cashback en centavos (value_cents).
      valueLabel: result.currency
        ? formatRewardValueLong(Number(result.value ?? result.value_cents ?? 0), toRewardCurrency(result.currency))
        : formatRewardValueLong(Number(result.value_cents ?? 0), "cashback"),
      expiresLabel: formatDateTime(result.expires_at),
      deliveredLabel: result.delivered_at ? formatDateTime(result.delivered_at) : null,
    };
  } catch (error) {
    console.error("merchant_redeem", error instanceof Error ? error.message : error);
    return { ok: false, error: "No se pudo validar el código. Revisa tu conexión e intenta de nuevo." };
  }
}

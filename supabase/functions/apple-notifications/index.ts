// Edge Function: apple-notifications
//
// App Store Server Notifications V2: Apple llama a esta URL cada vez que
// una suscripcion se renueva, se cancela, falla el cobro, entra en
// periodo de gracia o se reembolsa. Asi el servidor se entera aunque la
// persona no abra la app.
//
// Seguridad: el contenido del aviso NO se usa como verdad. Del aviso solo
// se toma el originalTransactionId; si corresponde a una suscripcion que
// ya tenemos, se consulta el estado real con el App Store Server API
// (autenticado con nuestra llave, igual que verify-apple-receipt) y eso es
// lo que se guarda. Un aviso falso, como mucho, provoca una consulta a
// Apple que devuelve la verdad.
//
// verify_jwt: false (Apple no manda JWT de Supabase). Se configura en
// App Store Connect > App > Informacion de la app > Notificaciones del
// servidor de App Store (Produccion y Sandbox, Version 2).

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const APPLE_BUNDLE_ID = Deno.env.get("APPLE_BUNDLE_ID")!;
const APPLE_ISSUER_ID = Deno.env.get("APPLE_ISSUER_ID")!;
const APPLE_KEY_ID = Deno.env.get("APPLE_KEY_ID")!;
const APPLE_PRIVATE_KEY = Deno.env.get("APPLE_PRIVATE_KEY")!;

function ok(body: unknown = { ok: true }): Response {
  return new Response(JSON.stringify(body), { headers: { "Content-Type": "application/json" } });
}

function decodeJWSPayload<T = Record<string, unknown>>(jws: string): T {
  const [, payload] = jws.split(".");
  const b64 = payload.replace(/-/g, "+").replace(/_/g, "/");
  const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
  const bytes = Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
  return JSON.parse(new TextDecoder().decode(bytes));
}

interface TransactionInfo {
  productId: string;
  transactionId: string;
  originalTransactionId: string;
  expiresDate?: number;
  gracePeriodExpiresDate?: number;
}

interface LastTransaction {
  status: number;
  signedTransactionInfo: string;
  signedRenewalInfo?: string;
}

function mapStatus(appleStatus: number): string {
  switch (appleStatus) {
    case 1: return "active";
    case 4: return "in_grace_period";
    case 5: return "revoked";
    case 2:
    case 3:
      return "expired";
    default:
      return "unknown";
  }
}

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function createAppleServerJWT(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const encoder = new TextEncoder();
  const header = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: APPLE_KEY_ID.trim(), typ: "JWT" })));
  const payload = base64url(encoder.encode(JSON.stringify({
    iss: APPLE_ISSUER_ID.trim(),
    iat: now,
    exp: now + 60 * 20,
    aud: "appstoreconnect-v1",
    bid: APPLE_BUNDLE_ID.trim(),
  })));
  const pkcs8 = (APPLE_PRIVATE_KEY ?? "")
    .replace(/\\n/g, "\n")
    .replace(/-----[A-Z ]+-----/g, "")
    .replace(/[^A-Za-z0-9+/=]/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pkcs8), (c) => c.charCodeAt(0)),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(`${header}.${payload}`));
  return `${header}.${payload}.${base64url(new Uint8Array(signature))}`;
}

/// Estado real en Apple. Prueba produccion y luego sandbox (401/404 en
/// produccion es normal para compras de prueba o antes de publicar).
async function fetchLastTransaction(originalTransactionId: string): Promise<LastTransaction | null> {
  const jwt = await createAppleServerJWT();
  for (const base of ["https://api.storekit.itunes.apple.com", "https://api.storekit-sandbox.itunes.apple.com"]) {
    const response = await fetch(`${base}/inApps/v1/subscriptions/${originalTransactionId}`, {
      headers: { Authorization: `Bearer ${jwt}` },
      signal: AbortSignal.timeout(15_000),
    });
    if (response.ok) {
      const data = await response.json() as { data?: { lastTransactions?: LastTransaction[] }[] };
      for (const group of data.data ?? []) {
        for (const tx of group.lastTransactions ?? []) {
          if (decodeJWSPayload<TransactionInfo>(tx.signedTransactionInfo).originalTransactionId === originalTransactionId) {
            return tx;
          }
        }
      }
      return null;
    }
    await response.body?.cancel();
    if (![400, 401, 404].includes(response.status)) {
      throw new Error(`${base} -> ${response.status}`);
    }
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return ok({ ok: true, info: "MonAvi App Store notifications" });

  let originalTransactionId: string | null = null;
  let notificationType = "";
  try {
    const body = await req.json() as { signedPayload?: string };
    if (!body.signedPayload) return ok({ ignored: "sin signedPayload" });
    const notification = decodeJWSPayload<{
      notificationType?: string;
      subtype?: string;
      data?: { bundleId?: string; signedTransactionInfo?: string };
    }>(body.signedPayload);
    notificationType = `${notification.notificationType ?? ""}${notification.subtype ? "/" + notification.subtype : ""}`;
    if (notification.data?.bundleId && notification.data.bundleId !== APPLE_BUNDLE_ID.trim()) {
      return ok({ ignored: "otro bundle" });
    }
    if (notification.data?.signedTransactionInfo) {
      originalTransactionId = decodeJWSPayload<TransactionInfo>(notification.data.signedTransactionInfo).originalTransactionId;
    }
  } catch {
    return ok({ ignored: "aviso ilegible" });
  }

  // TEST (boton "Enviar notificacion de prueba") no trae transaccion.
  if (!originalTransactionId || !/^[0-9]{1,30}$/.test(originalTransactionId)) {
    console.log("apple-notifications", notificationType, "sin transaccion");
    return ok({ received: notificationType });
  }

  try {
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const { data: rows } = await supabase
      .from("subscriptions")
      .select("user_id")
      .eq("apple_original_transaction_id", originalTransactionId);
    if (!rows || rows.length === 0) {
      // Aun no la conocemos (la app la registra al comprar): nada que hacer.
      return ok({ ignored: "suscripcion desconocida", type: notificationType });
    }

    const last = await fetchLastTransaction(originalTransactionId);
    if (!last) return ok({ ignored: "no encontrada en Apple", type: notificationType });

    const tx = decodeJWSPayload<TransactionInfo>(last.signedTransactionInfo);
    const renewal = last.signedRenewalInfo ? decodeJWSPayload<TransactionInfo>(last.signedRenewalInfo) : null;
    const status = mapStatus(last.status);
    const expiresMillis = status === "in_grace_period" && renewal?.gracePeriodExpiresDate
      ? renewal.gracePeriodExpiresDate
      : tx.expiresDate;

    for (const row of rows as { user_id: string }[]) {
      const { error } = await supabase.from("subscriptions").upsert({
        user_id: row.user_id,
        product_id: tx.productId,
        status,
        apple_transaction_id: tx.transactionId,
        apple_original_transaction_id: tx.originalTransactionId,
        expires_at: expiresMillis ? new Date(expiresMillis).toISOString() : null,
      });
      if (error) throw error;
    }
    console.log("apple-notifications", notificationType, status);
    return ok({ updated: rows.length, status, type: notificationType });
  } catch (error) {
    console.error("apple-notifications", notificationType, String(error));
    // 500 para que Apple reintente mas tarde.
    return new Response(JSON.stringify({ error: "temporal" }), { status: 500 });
  }
});

// Edge Function: verify-apple-receipt
//
// Recibe {userId, originalTransactionId} desde la app (despues de una compra
// o restauracion via StoreKit 2), consulta el App Store Server API de Apple
// (GET /inApps/v1/subscriptions/{originalTransactionId} — no el endpoint de
// una sola transaccion, que no trae el periodo de gracia de facturacion) y
// hace upsert en public.subscriptions con la service role key.
//
// IMPORTANTE — sin probar: este entorno no tiene Deno ni acceso a un sandbox
// de Apple, asi que esta funcion no se ha ejecutado ni contra sandbox ni
// contra produccion. Antes de usarla con compras reales: probar con
// `supabase functions serve` + una compra sandbox, y revisar que el
// decodificado de la JWS de Apple sea correcto.
//
// Ademas, por simplicidad esta version decodifica el payload de la JWS que
// regresa Apple (signedTransactionInfo) SIN validar la cadena de
// certificados x5c contra el root de Apple. Para produccion real conviene
// verificar esa firma (ver "Verifying the signature" en la doc de Apple:
// https://developer.apple.com/documentation/appstoreserverapi/verifying-the-signatures).
//
// Seguridad (ver supabase/functions/README_SECURITY.md): userId SIEMPRE
// del JWT verificado (nunca del body) — antes esta funcion confiaba en el
// userId que mandara el cliente y lo usaba con la service role key (que
// salta RLS) para hacer upsert en subscriptions; cualquier usuario
// autenticado podia pisar la suscripcion de otro con su propio
// originalTransactionId. Rate limit: 10 llamadas / 10 minutos.
//
// Secrets necesarios (supabase secrets set ...):
//   APPLE_BUNDLE_ID              -> ej. app.alza
//   APPLE_ISSUER_ID              -> App Store Connect > Users and Access > Integrations > In-App Purchase
//   APPLE_KEY_ID                 -> id de la "In-App Purchase Key" (.p8)
//   APPLE_PRIVATE_KEY             -> contenido del .p8 (con -----BEGIN PRIVATE KEY-----)
//   APPLE_ENVIRONMENT (opcional) -> "sandbox" para forzar sandbox; si no se
//                                    pone, intenta produccion y cae a sandbox

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const APPLE_BUNDLE_ID = Deno.env.get("APPLE_BUNDLE_ID")!;
const APPLE_ISSUER_ID = Deno.env.get("APPLE_ISSUER_ID")!;
const APPLE_KEY_ID = Deno.env.get("APPLE_KEY_ID")!;
const APPLE_PRIVATE_KEY = Deno.env.get("APPLE_PRIVATE_KEY")!;
const FORCED_ENVIRONMENT = Deno.env.get("APPLE_ENVIRONMENT");

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
    const originalTransactionId = body?.originalTransactionId;
    if (typeof originalTransactionId !== "string" || originalTransactionId.length === 0 || originalTransactionId.length > 100) {
      return jsonResponse({ error: "originalTransactionId invalido" }, 400);
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const allowed = await checkRateLimit(supabase, userId, "verify-apple-receipt", 10, 600);
    if (!allowed) {
      return jsonResponse({ error: "Demasiadas solicitudes, intenta en unos minutos." }, 429);
    }

    const jwt = await createAppleServerJWT();
    const statusInfo = await fetchSubscriptionStatus(originalTransactionId, jwt);
    const lastTransaction = findLastTransaction(statusInfo, originalTransactionId);
    if (!lastTransaction) {
      return jsonResponse({ error: "No se encontro la suscripcion en Apple." }, 404);
    }

    const decoded = decodeJWSPayload(lastTransaction.signedTransactionInfo);
    const renewalInfo = lastTransaction.signedRenewalInfo
      ? decodeJWSPayload(lastTransaction.signedRenewalInfo)
      : null;

    const status = mapStatus(lastTransaction.status);
    // En gracia, Apple sigue dando acceso hasta gracePeriodExpiresDate (no
    // hasta expiresDate, que ya quedo en el pasado — por eso fallo el cobro
    // en primer lugar). Fuera de gracia, expiresDate es la fecha real.
    const expiresAtMillis = status === "in_grace_period" && renewalInfo?.gracePeriodExpiresDate
      ? renewalInfo.gracePeriodExpiresDate
      : decoded.expiresDate;
    const expiresAt = expiresAtMillis ? new Date(expiresAtMillis).toISOString() : null;

    const { error } = await supabase.from("subscriptions").upsert({
      user_id: userId,
      product_id: decoded.productId,
      status,
      apple_transaction_id: decoded.transactionId,
      apple_original_transaction_id: decoded.originalTransactionId,
      expires_at: expiresAt,
    });
    if (error) throw error;

    return jsonResponse({ status, expiresAt });
  } catch (error) {
    console.error(error);
    return jsonResponse({ error: String(error) }, 500);
  }
});

/** Estados del App Store Server API (campo "status" en lastTransactions):
 * 1 activa, 2 expirada, 3 en reintento de cobro (sin gracia configurada o
 * ya agotada — sin acceso), 4 en periodo de gracia de facturacion (CON
 * acceso, ver supabase/functions/README para activarlo en App Store
 * Connect), 5 revocada (reembolso). */
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

interface LastTransaction {
  status: number;
  signedTransactionInfo: string;
  signedRenewalInfo?: string;
}

/** GET /inApps/v1/subscriptions/{originalTransactionId}: a diferencia del
 * endpoint de una sola transaccion, este trae el estado real de la
 * suscripcion (activa/gracia/expirada/revocada) en signedRenewalInfo —
 * sin este, no hay forma de saber que un usuario esta en periodo de
 * gracia de facturacion. */
async function fetchSubscriptionStatus(originalTransactionId: string, jwt: string) {
  const environments = FORCED_ENVIRONMENT === "sandbox"
    ? ["https://api.storekit-sandbox.itunes.apple.com"]
    : ["https://api.storekit.itunes.apple.com", "https://api.storekit-sandbox.itunes.apple.com"];

  let lastError: unknown;
  for (const base of environments) {
    const response = await fetch(`${base}/inApps/v1/subscriptions/${originalTransactionId}`, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    if (response.ok) {
      return await response.json();
    }
    lastError = new Error(`${base} -> ${response.status} ${await response.text()}`);
  }
  throw lastError;
}

/** La respuesta trae un grupo por subscriptionGroupIdentifier (hoy solo
 * tenemos uno, "Avi Pro") con su lastTransactions — busca la que coincide
 * con el originalTransactionId que mando el cliente, por si en el futuro
 * hay mas de un grupo. */
function findLastTransaction(
  statusInfo: { data?: { lastTransactions?: LastTransaction[] }[] },
  originalTransactionId: string,
): LastTransaction | null {
  for (const group of statusInfo.data ?? []) {
    for (const tx of group.lastTransactions ?? []) {
      const decoded = decodeJWSPayload(tx.signedTransactionInfo);
      if (decoded.originalTransactionId === originalTransactionId) return tx;
    }
  }
  return null;
}

/** Decodifica (sin verificar firma) el payload base64url de una JWS. */
function decodeJWSPayload(jws: string): {
  productId: string;
  transactionId: string;
  originalTransactionId: string;
  expiresDate?: number;
  revocationDate?: number;
  gracePeriodExpiresDate?: number;
} {
  const [, payload] = jws.split(".");
  const json = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
  return JSON.parse(json);
}

/** Firma un JWT ES256 para autenticarse contra el App Store Server API. */
async function createAppleServerJWT(): Promise<string> {
  const header = { alg: "ES256", kid: APPLE_KEY_ID, typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: APPLE_ISSUER_ID,
    iat: now,
    exp: now + 60 * 20,
    aud: "appstoreconnect-v1",
    bid: APPLE_BUNDLE_ID,
  };

  const encoder = new TextEncoder();
  const headerB64 = base64url(encoder.encode(JSON.stringify(header)));
  const payloadB64 = base64url(encoder.encode(JSON.stringify(payload)));
  const signingInput = `${headerB64}.${payloadB64}`;

  const key = await importApplePrivateKey(APPLE_PRIVATE_KEY);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(signingInput),
  );

  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

async function importApplePrivateKey(pem: string): Promise<CryptoKey> {
  const pkcs8 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = Uint8Array.from(atob(pkcs8), (c) => c.charCodeAt(0));

  return await crypto.subtle.importKey(
    "pkcs8",
    binary,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

function base64url(bytes: Uint8Array): string {
  let str = btoa(String.fromCharCode(...bytes));
  return str.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

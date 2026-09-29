// Edge Function: verify-apple-receipt
//
// Recibe {userId, originalTransactionId} desde la app (despues de una compra
// o restauracion via StoreKit 2), consulta el App Store Server API de Apple
// para confirmar el estado real de la suscripcion, y hace upsert en
// public.subscriptions con la service role key.
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

Deno.serve(async (req) => {
  try {
    const { userId, originalTransactionId } = await req.json();
    if (!userId || !originalTransactionId) {
      return new Response(
        JSON.stringify({ error: "userId and originalTransactionId are required" }),
        { status: 400 },
      );
    }

    const jwt = await createAppleServerJWT();
    const transactionInfo = await fetchTransactionInfo(originalTransactionId, jwt);
    const decoded = decodeJWSPayload(transactionInfo.signedTransactionInfo);

    const status = mapStatus(decoded);
    const expiresAt = decoded.expiresDate ? new Date(decoded.expiresDate).toISOString() : null;

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const { error } = await supabase.from("subscriptions").upsert({
      user_id: userId,
      product_id: decoded.productId,
      status,
      apple_transaction_id: decoded.transactionId,
      apple_original_transaction_id: decoded.originalTransactionId,
      expires_at: expiresAt,
    });
    if (error) throw error;

    return new Response(JSON.stringify({ status, expiresAt }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error(error);
    return new Response(JSON.stringify({ error: String(error) }), { status: 500 });
  }
});

function mapStatus(decoded: { revocationDate?: number; expiresDate?: number }): string {
  if (decoded.revocationDate) return "revoked";
  if (decoded.expiresDate && decoded.expiresDate < Date.now()) return "expired";
  return "active";
}

async function fetchTransactionInfo(transactionId: string, jwt: string) {
  const environments = FORCED_ENVIRONMENT === "sandbox"
    ? ["https://api.storekit-sandbox.itunes.apple.com"]
    : ["https://api.storekit.itunes.apple.com", "https://api.storekit-sandbox.itunes.apple.com"];

  let lastError: unknown;
  for (const base of environments) {
    const response = await fetch(`${base}/inApps/v1/transactions/${transactionId}`, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    if (response.ok) {
      return await response.json();
    }
    lastError = new Error(`${base} -> ${response.status} ${await response.text()}`);
  }
  throw lastError;
}

/** Decodifica (sin verificar firma) el payload base64url de una JWS. */
function decodeJWSPayload(jws: string): {
  productId: string;
  transactionId: string;
  originalTransactionId: string;
  expiresDate?: number;
  revocationDate?: number;
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

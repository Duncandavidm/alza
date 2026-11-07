// Edge Function: push-check
//
// Diagnostico de la configuracion de APNs, sin revelar ningun secreto:
// firma un token con APNS_PRIVATE_KEY / APNS_KEY_ID / APNS_TEAM_ID y lo
// manda a Apple con un dispositivo FALSO. Si Apple responde
// "BadDeviceToken", la llave es valida (solo el dispositivo no existe);
// si responde "InvalidProviderToken", algun secreto esta mal.
//
// Opcional: body {"userId": "..."} manda un push de prueba real a los
// iPhone de ese usuario.
//
// Exige x-admin-secret (igual que los demas jobs). verify_jwt: false.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { apnsConfigured, sendPushToUser } from "./apns.ts";

const ADMIN_JOB_SECRET = Deno.env.get("ADMIN_JOB_SECRET")!;
const KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY") ?? "";
const BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "app.monavi";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body, null, 2), { status, headers: { "Content-Type": "application/json" } });
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function signJwt(): Promise<string> {
  const pem = PRIVATE_KEY.replace(/-----BEGIN [^-]+-----/g, "").replace(/-----END [^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const enc = (v: unknown) => base64Url(new TextEncoder().encode(JSON.stringify(v)));
  const input = `${enc({ alg: "ES256", kid: KEY_ID })}.${enc({ iss: TEAM_ID, iat: Math.floor(Date.now() / 1000) })}`;
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input)));
  return `${input}.${base64Url(sig)}`;
}

async function probe(host: string, jwt: string) {
  const fakeToken = "0".repeat(64);
  const response = await fetch(`${host}/3/device/${fakeToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": BUNDLE_ID,
      "apns-push-type": "alert",
      "content-type": "application/json",
    },
    body: JSON.stringify({ aps: { alert: "diagnostico" } }),
  });
  const text = await response.text();
  let reason = text;
  try { reason = JSON.parse(text).reason ?? text; } catch { /* texto plano */ }
  return {
    status: response.status,
    reason,
    keyAccepted: reason === "BadDeviceToken",
  };
}

Deno.serve(async (req) => {
  if (req.headers.get("x-admin-secret") !== ADMIN_JOB_SECRET) return json({ error: "No autorizado" }, 401);

  const report: Record<string, unknown> = {
    secretsPresent: { APNS_KEY_ID: KEY_ID.length > 0, APNS_TEAM_ID: TEAM_ID.length > 0, APNS_PRIVATE_KEY: PRIVATE_KEY.length > 0 },
    keyIdLength: KEY_ID.trim().length,
    keyIdHasSpaces: KEY_ID !== KEY_ID.trim(),
    teamIdMatches: TEAM_ID.trim() === "S7ZS3G5284",
    teamIdHasSpaces: TEAM_ID !== TEAM_ID.trim(),
    privateKeyHasHeader: PRIVATE_KEY.includes("BEGIN PRIVATE KEY"),
    bundleId: BUNDLE_ID,
    apnsConfigured: apnsConfigured(),
  };

  let jwt: string;
  try {
    jwt = await signJwt();
    report.signing = "ok";
  } catch (error) {
    report.signing = `fallo: ${String(error)}`;
    return json(report);
  }

  report.sandbox = await probe("https://api.sandbox.push.apple.com", jwt);
  report.production = await probe("https://api.push.apple.com", jwt);

  const body = await req.json().catch(() => ({}));
  if (typeof body?.userId === "string") {
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    report.testPush = await sendPushToUser(supabase, body.userId, {
      title: "MonAvi: notificaciones listas ✅",
      body: "Así te avisaremos cuando sumes puntos.",
      data: { screen: "points" },
    });
  }

  return json(report);
});

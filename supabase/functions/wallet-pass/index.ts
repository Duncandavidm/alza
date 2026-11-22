// Edge Function: wallet-pass (1.0.5)
//
// Arma y firma el pase de Apple Wallet (.pkpass) de un cupon o canje del
// usuario: el QR y el codigo que se muestran en caja, el comercio, el
// vencimiento y la ubicacion del local (Wallet lo sugiere en la pantalla
// bloqueada al pasar cerca).
//
//   POST {"check": true}             -> {"enabled": true|false}
//   POST {"redemption_id": "<uuid>"} -> el .pkpass (application/vnd.apple.pkpass)
//   POST {"selftest": true} + x-admin-secret -> firma un pase de prueba y
//        dice si el certificado sirve (sin devolver ningun secreto)
//
// verify_jwt: false: la funcion valida la sesion del usuario con
// auth.getUser (solo el dueño del canje), o x-admin-secret para la
// autoprueba. Necesita estos secretos de
// Supabase, que pone el dueño del proyecto (nunca en el codigo):
//   WALLET_PASS_TYPE_ID   p. ej. pass.app.monavi.cupon (Apple Developer > Identifiers)
//   WALLET_P12_BASE64     el certificado del Pass Type ID exportado como .p12, en base64
//   WALLET_P12_PASSWORD   la contraseña con que se exporto el .p12 (puede ir vacia)
// Opcionales: WALLET_TEAM_ID (por defecto el del proyecto) y WALLET_WWDR_PEM
// (si no, se baja el certificado intermedio WWDR G4 publico de Apple).

import { createClient } from "jsr:@supabase/supabase-js@2";
// @deno-types="npm:@types/node-forge@1.3.11"
import forge from "npm:node-forge@1.3.1";
import { zipSync } from "npm:fflate@0.8.2";
import { PASS_IMAGES } from "./assets.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ADMIN_JOB_SECRET = Deno.env.get("ADMIN_JOB_SECRET") ?? "";
const PASS_TYPE_ID = Deno.env.get("WALLET_PASS_TYPE_ID") ?? "";
const P12_BASE64 = (Deno.env.get("WALLET_P12_BASE64") ?? "").replace(/\s+/g, "");
const P12_PASSWORD = Deno.env.get("WALLET_P12_PASSWORD") ?? "";
const TEAM_ID = Deno.env.get("WALLET_TEAM_ID") ?? "S7ZS3G5284";
const WWDR_PEM = Deno.env.get("WALLET_WWDR_PEM") ?? "";
const WWDR_URL = "https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer";
const REDEEM_BASE_URL = "https://monavi.maday.app/canjear";

const CORS_HEADERS = {
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-admin-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...CORS_HEADERS } });
}

function configured(): boolean {
  return Boolean(PASS_TYPE_ID && P12_BASE64);
}

/// El usuario de la sesion, validada con Supabase Auth (firma y vigencia).
async function verifiedUserId(req: Request): Promise<string | null> {
  const header = req.headers.get("Authorization");
  if (!header?.startsWith("Bearer ")) return null;
  const token = header.slice(7);
  if (token.split(".").length !== 3) return null;
  const { data, error } = await createClient(SUPABASE_URL, SERVICE_ROLE_KEY).auth.getUser(token);
  return error || !data.user ? null : data.user.id;
}

/// Autoprueba: abre el .p12, baja el WWDR, firma un pase de prueba y
/// devuelve solo datos publicos del certificado.
async function selfTest(): Promise<Record<string, unknown>> {
  const result: Record<string, unknown> = {
    configured: configured(),
    pass_type_id: PASS_TYPE_ID || null,
    team_id: TEAM_ID,
    password_set: P12_PASSWORD.length > 0,
  };
  if (!configured()) return { ...result, ok: false, error: "Faltan WALLET_PASS_TYPE_ID o WALLET_P12_BASE64." };
  let step = "abrir el .p12";
  try {
    const identity = await loadIdentity();
    step = "revisar el certificado";
    const cn = String(identity.cert.subject.getField("CN")?.value ?? "");
    const uid = String(identity.cert.subject.getField({ type: "0.9.2342.19200300.100.1.1" })?.value ?? "");
    const certPublic = identity.cert.publicKey as forge.pki.rsa.PublicKey;
    const key = identity.key as forge.pki.rsa.PrivateKey;
    Object.assign(result, {
      cert_subject: cn,
      cert_pass_type_id: uid || null,
      cert_matches_pass_type_id: uid ? uid === PASS_TYPE_ID : cn.includes(PASS_TYPE_ID),
      cert_valid_from: identity.cert.validity.notBefore.toISOString(),
      cert_valid_until: identity.cert.validity.notAfter.toISOString(),
      key_matches_cert: certPublic.n.equals(key.n),
      wwdr_subject: String(identity.wwdr.subject.getField("CN")?.value ?? ""),
    });
    step = "firmar un pase de prueba";
    const pkpass = await buildPass({
      id: crypto.randomUUID(),
      user_id: "00000000-0000-0000-0000-000000000000",
      code: "PRUEBA",
      status: "emitido",
      expires_at: new Date(Date.now() + 86_400_000).toISOString(),
      gift_message: null,
      merchant_id: "00000000-0000-0000-0000-000000000000",
      reward_items: { name: "Pase de prueba", description: null },
      partner_merchants: { name: "MonAvi", address: null, latitude: null, longitude: null },
    }, []);
    return { ...result, ok: Boolean(result.key_matches_cert), pkpass_bytes: pkpass.length };
  } catch (err) {
    return { ...result, ok: false, step, error: String((err as { message?: string })?.message ?? err) };
  }
}

// ---------- bytes <-> cadenas binarias (forge trabaja con estas) ----------

function bytesToBinary(bytes: Uint8Array): string {
  let out = "";
  for (let i = 0; i < bytes.length; i += 0x8000) out += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return out;
}

function binaryToBytes(binary: string): Uint8Array {
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i) & 0xff;
  return out;
}

function base64ToBytes(value: string): Uint8Array {
  return binaryToBytes(atob(value));
}

async function sha1Hex(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-1", bytes));
  return Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
}

// ---------- certificados ----------

type Identity = { key: forge.pki.PrivateKey; cert: forge.pki.Certificate; wwdr: forge.pki.Certificate };
let cachedIdentity: Identity | null = null;

async function loadIdentity(): Promise<Identity> {
  if (cachedIdentity) return cachedIdentity;
  const p12 = forge.pkcs12.pkcs12FromAsn1(forge.asn1.fromDer(atob(P12_BASE64)), P12_PASSWORD);
  const shrouded = p12.getBags({ bagType: forge.pki.oids.pkcs8ShroudedKeyBag })[forge.pki.oids.pkcs8ShroudedKeyBag] ?? [];
  const plain = p12.getBags({ bagType: forge.pki.oids.keyBag })[forge.pki.oids.keyBag] ?? [];
  const key = shrouded[0]?.key ?? plain[0]?.key;
  const certs = p12.getBags({ bagType: forge.pki.oids.certBag })[forge.pki.oids.certBag] ?? [];
  // El del Pass Type ID (no el WWDR, si el .p12 lo trae tambien).
  const cert = certs.map((bag) => bag.cert).find((c) => c && !/Worldwide Developer Relations/i.test(c.subject.getField("CN")?.value ?? ""));
  if (!key || !cert) throw new Error("El .p12 no trae la llave privada y el certificado del Pass Type ID.");

  let wwdr: forge.pki.Certificate;
  if (WWDR_PEM) {
    wwdr = forge.pki.certificateFromPem(WWDR_PEM.replace(/\\n/g, "\n"));
  } else {
    const response = await fetch(WWDR_URL);
    if (!response.ok) throw new Error(`No se pudo bajar el certificado WWDR de Apple (${response.status}).`);
    const der = new Uint8Array(await response.arrayBuffer());
    wwdr = forge.pki.certificateFromAsn1(forge.asn1.fromDer(bytesToBinary(der)));
  }
  cachedIdentity = { key, cert, wwdr };
  return cachedIdentity;
}

function sign(manifest: Uint8Array, identity: Identity): Uint8Array {
  const p7 = forge.pkcs7.createSignedData();
  p7.content = forge.util.createBuffer(bytesToBinary(manifest));
  p7.addCertificate(identity.cert);
  p7.addCertificate(identity.wwdr);
  p7.addSigner({
    key: identity.key as forge.pki.rsa.PrivateKey,
    certificate: identity.cert,
    digestAlgorithm: forge.pki.oids.sha256,
    authenticatedAttributes: [
      { type: forge.pki.oids.contentType, value: forge.pki.oids.data },
      { type: forge.pki.oids.messageDigest },
      { type: forge.pki.oids.signingTime, value: new Date() as unknown as string },
    ],
  });
  p7.sign({ detached: true });
  return binaryToBytes(forge.asn1.toDer(p7.toAsn1()).getBytes());
}

// ---------- el pase ----------

type RedemptionRow = {
  id: string;
  user_id: string;
  code: string;
  status: string;
  expires_at: string;
  gift_message: string | null;
  merchant_id: string;
  reward_items: { name: string; description: string | null } | null;
  partner_merchants: { name: string; address: string | null; latitude: number | null; longitude: number | null } | null;
};

function passJson(row: RedemptionRow, locations: { latitude: number; longitude: number }[]) {
  const merchant = row.partner_merchants?.name ?? "Comercio aliado";
  const item = row.reward_items?.name ?? "Tu cupón";
  const redeemURL = `${REDEEM_BASE_URL}?code=${encodeURIComponent(row.code)}`;
  const backFields: { key: string; label: string; value: string }[] = [
    { key: "how", label: "Cómo usarlo", value: "Muestra este código en caja antes de pagar. El cajero lo valida en MonAvi." },
  ];
  if (row.reward_items?.description) backFields.push({ key: "conditions", label: "Condiciones", value: row.reward_items.description });
  if (row.gift_message) backFields.push({ key: "message", label: "Mensaje", value: row.gift_message });
  if (row.partner_merchants?.address) backFields.push({ key: "address", label: "Dirección", value: row.partner_merchants.address });

  return {
    formatVersion: 1,
    passTypeIdentifier: PASS_TYPE_ID,
    teamIdentifier: TEAM_ID,
    serialNumber: row.id,
    organizationName: "MonAvi",
    description: `Cupón de ${merchant}`,
    logoText: "MonAvi",
    foregroundColor: "rgb(255, 255, 255)",
    labelColor: "rgb(205, 245, 232)",
    backgroundColor: "rgb(0, 140, 113)",
    expirationDate: row.expires_at,
    barcodes: [{ format: "PKBarcodeFormatQR", message: redeemURL, messageEncoding: "iso-8859-1", altText: row.code }],
    barcode: { format: "PKBarcodeFormatQR", message: redeemURL, messageEncoding: "iso-8859-1", altText: row.code },
    locations: locations.slice(0, 10).map((l) => ({ ...l, relevantText: `Tienes ${item} en ${merchant}` })),
    coupon: {
      primaryFields: [{ key: "offer", label: merchant.toUpperCase(), value: item }],
      secondaryFields: [{ key: "code", label: "CÓDIGO", value: row.code }],
      auxiliaryFields: [{ key: "expires", label: "VENCE", value: row.expires_at, dateStyle: "PKDateStyleMedium", timeStyle: "PKDateStyleNone" }],
      backFields,
    },
  };
}

async function buildPass(row: RedemptionRow, locations: { latitude: number; longitude: number }[]): Promise<Uint8Array> {
  const identity = await loadIdentity();
  const files: Record<string, Uint8Array> = {
    "pass.json": new TextEncoder().encode(JSON.stringify(passJson(row, locations))),
  };
  for (const [name, base64] of Object.entries(PASS_IMAGES)) files[name] = base64ToBytes(base64);

  const manifest: Record<string, string> = {};
  for (const [name, bytes] of Object.entries(files)) manifest[name] = await sha1Hex(bytes);
  const manifestBytes = new TextEncoder().encode(JSON.stringify(manifest));
  files["manifest.json"] = manifestBytes;
  files["signature"] = sign(manifestBytes, identity);
  return zipSync(files, { level: 6 });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);

  let body: { check?: boolean; redemption_id?: string; selftest?: boolean } = {};
  try { body = await req.json(); } catch { /* vacio */ }

  if (body.selftest) {
    if (!ADMIN_JOB_SECRET || req.headers.get("x-admin-secret") !== ADMIN_JOB_SECRET) return json({ error: "No autorizado" }, 401);
    return json(await selfTest());
  }

  const userId = await verifiedUserId(req);
  if (!userId) return json({ error: "No autorizado" }, 401);

  if (body.check) return json({ enabled: configured() });
  if (!configured()) return json({ error: "Apple Wallet todavía no está configurado." }, 501);

  const redemptionId = String(body.redemption_id ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(redemptionId)) return json({ error: "Canje inválido." }, 400);

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const { data: row, error } = await supabase
    .from("reward_redemptions")
    .select("id, user_id, code, status, expires_at, gift_message, merchant_id, reward_items(name, description), partner_merchants(name, address, latitude, longitude)")
    .eq("id", redemptionId)
    .eq("user_id", userId)
    .maybeSingle<RedemptionRow>();
  if (error) return json({ error: error.message }, 500);
  if (!row) return json({ error: "No encontramos ese canje." }, 404);
  if (row.status !== "emitido" || new Date(row.expires_at) < new Date()) {
    return json({ error: "Este código ya se usó o venció." }, 409);
  }

  const locations: { latitude: number; longitude: number }[] = [];
  const main = row.partner_merchants;
  if (main?.latitude != null && main?.longitude != null) locations.push({ latitude: main.latitude, longitude: main.longitude });
  const { data: branches } = await supabase
    .from("merchant_branches")
    .select("latitude, longitude")
    .eq("merchant_id", row.merchant_id)
    .not("latitude", "is", null)
    .limit(9);
  for (const b of (branches ?? []) as { latitude: number | null; longitude: number | null }[]) {
    if (b.latitude != null && b.longitude != null) locations.push({ latitude: b.latitude, longitude: b.longitude });
  }

  try {
    const pkpass = await buildPass(row, locations);
    return new Response(pkpass, {
      headers: {
        "Content-Type": "application/vnd.apple.pkpass",
        "Content-Disposition": `attachment; filename="monavi-${row.code}.pkpass"`,
        ...CORS_HEADERS,
      },
    });
  } catch (err) {
    console.error("wallet-pass", err);
    return json({ error: "No se pudo firmar el pase. Revisa el certificado de Apple Wallet." }, 500);
  }
});

// Notificaciones push por APNs (Apple Push Notification service), con la
// autenticacion por token (.p8) que Apple recomienda: un JWT ES256 firmado
// con la llave del equipo, valido hasta 1 hora.
//
// Secrets necesarios (Edge Functions > Secrets). Si falta alguno, no se
// envia nada y la funcion sigue normal (los puntos se suman igual):
//   APNS_KEY_ID       Key ID de la llave (10 caracteres)
//   APNS_TEAM_ID      Team ID de Apple Developer (S7ZS3G5284)
//   APNS_PRIVATE_KEY  contenido completo del archivo AuthKey_XXXX.p8
//   APNS_BUNDLE_ID    opcional, por defecto app.monavi
//
// Los tokens de cada iPhone viven en public.device_push_tokens (los guarda
// la app). Un build de Xcode usa el ambiente "sandbox"; TestFlight y App
// Store usan "production" — cada token sabe a cual pertenece.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID");
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID");
const APNS_PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY");
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "app.monavi";

export function apnsConfigured(): boolean {
  return Boolean(APNS_KEY_ID && APNS_TEAM_ID && APNS_PRIVATE_KEY);
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

async function providerToken(): Promise<string> {
  // Apple pide renovarlo entre 20 y 60 minutos.
  if (cachedToken && Date.now() - cachedToken.createdAt < 40 * 60 * 1000) {
    return cachedToken.value;
  }

  const pem = (APNS_PRIVATE_KEY ?? "")
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (char) => char.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const header = base64UrlJson({ alg: "ES256", kid: APNS_KEY_ID });
  const claims = base64UrlJson({ iss: APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) });
  const signingInput = `${header}.${claims}`;
  // WebCrypto devuelve la firma ECDSA en formato r||s (64 bytes), que es
  // exactamente lo que pide un JWT ES256.
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput)),
  );

  const value = `${signingInput}.${base64Url(signature)}`;
  cachedToken = { value, createdAt: Date.now() };
  return value;
}

export interface PushMessage {
  title: string;
  body: string;
  /// Datos extra para la app (ej. { screen: "points" }).
  data?: Record<string, unknown>;
  threadId?: string;
  /// Imagen a la derecha del aviso (logo del comercio o foto del premio).
  /// La baja la extension MonAviNotificationService de la app 1.0.3+; en
  /// versiones viejas el aviso llega igual, sin imagen.
  imageUrl?: string | null;
  /// Versión en inglés (1.1.0): se usa si la persona tiene la app en inglés
  /// (profiles.language = 'en'). Sin ella, todos reciben el texto en español.
  en?: { title: string; body: string };
}

/// Ids de las personas con la app en inglés (profiles.language = 'en').
export async function englishUserIds(supabase: SupabaseClient, userIds: string[]): Promise<Set<string>> {
  const english = new Set<string>();
  for (let i = 0; i < userIds.length; i += 300) {
    const { data, error } = await supabase
      .from("profiles")
      .select("id")
      .in("id", userIds.slice(i, i + 300))
      .eq("language", "en");
    if (error) {
      console.error("profiles.language", error.message);
      continue;
    }
    for (const row of (data ?? []) as { id: string }[]) english.add(row.id);
  }
  return english;
}

/// El mensaje en el idioma de la persona.
function localized(message: PushMessage, english: boolean): PushMessage {
  return english && message.en ? { ...message, title: message.en.title, body: message.en.body } : message;
}

function buildPayload(message: PushMessage, defaultThread: string): string {
  const image = message.imageUrl && /^https:\/\//i.test(message.imageUrl) ? message.imageUrl : null;
  return JSON.stringify({
    aps: {
      alert: { title: message.title, body: message.body },
      sound: "monavi-alert.wav",
      "thread-id": message.threadId ?? defaultThread,
      "interruption-level": "active",
      ...(image ? { "mutable-content": 1 } : {}),
    },
    ...(image ? { image_url: image } : {}),
    ...(message.data ?? {}),
  });
}

/// Envia `message` a todos los iPhone del usuario. Nunca lanza: un fallo
/// de push no debe tumbar la verificacion de facturas.
export async function sendPushToUser(
  supabase: SupabaseClient,
  userId: string,
  message: PushMessage,
): Promise<{ sent: number; failed: number; skipped?: string }> {
  if (!apnsConfigured()) return { sent: 0, failed: 0, skipped: "apns_not_configured" };

  const { data: tokens, error } = await supabase
    .from("device_push_tokens")
    .select("token, environment")
    .eq("user_id", userId);
  if (error || !tokens || tokens.length === 0) return { sent: 0, failed: 0, skipped: "no_tokens" };

  let jwt: string;
  try {
    jwt = await providerToken();
  } catch (signError) {
    console.error("APNs: no se pudo firmar el token (revisa APNS_PRIVATE_KEY)", String(signError));
    return { sent: 0, failed: tokens.length, skipped: "bad_key" };
  }

  const english = message.en ? (await englishUserIds(supabase, [userId])).has(userId) : false;
  const payload = buildPayload(localized(message, english), "monavi-puntos");

  let sent = 0;
  let failed = 0;
  for (const row of tokens as { token: string; environment: string }[]) {
    const host = row.environment === "production"
      ? "https://api.push.apple.com"
      : "https://api.sandbox.push.apple.com";
    try {
      const response = await fetch(`${host}/3/device/${row.token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": APNS_BUNDLE_ID,
          "apns-push-type": "alert",
          "apns-priority": "10",
          "content-type": "application/json",
        },
        body: payload,
      });

      if (response.ok) {
        sent++;
        continue;
      }

      failed++;
      const reason = await response.text();
      // El iPhone desinstalo la app o el token ya no sirve: se borra.
      if (response.status === 410 || reason.includes("BadDeviceToken") || reason.includes("Unregistered")) {
        await supabase.from("device_push_tokens").delete().eq("token", row.token);
      } else {
        console.error("APNs rechazo el envio", response.status, reason);
      }
    } catch (networkError) {
      failed++;
      console.error("APNs: error de red", String(networkError));
    }
  }
  return { sent, failed };
}

/// Envio masivo: manda `message` a muchos usuarios a la vez (tokens en
/// bloque y varios envios en paralelo). Devuelve cuantos iPhone lo
/// recibieron y a cuantas personas les llego al menos uno.
export async function sendPushToUsers(
  supabase: SupabaseClient,
  userIds: string[],
  message: PushMessage,
  concurrency = 20,
): Promise<{ sent: number; failed: number; people: number; skipped?: string }> {
  if (!apnsConfigured()) return { sent: 0, failed: 0, people: 0, skipped: "apns_not_configured" };
  if (userIds.length === 0) return { sent: 0, failed: 0, people: 0 };

  const rows: { token: string; environment: string; user_id: string }[] = [];
  for (let i = 0; i < userIds.length; i += 300) {
    const { data, error } = await supabase
      .from("device_push_tokens")
      .select("token, environment, user_id")
      .in("user_id", userIds.slice(i, i + 300));
    if (error) throw error;
    rows.push(...((data ?? []) as typeof rows));
  }
  if (rows.length === 0) return { sent: 0, failed: 0, people: 0, skipped: "no_tokens" };

  const jwt = await providerToken();
  const english = message.en ? await englishUserIds(supabase, userIds) : new Set<string>();
  const payloadEs = buildPayload(message, "monavi-ofertas");
  const payloadEn = message.en ? buildPayload(localized(message, true), "monavi-ofertas") : payloadEs;

  let sent = 0;
  let failed = 0;
  const reached = new Set<string>();
  let index = 0;
  async function worker() {
    while (index < rows.length) {
      const row = rows[index++];
      const host = row.environment === "production" ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
      try {
        const response = await fetch(`${host}/3/device/${row.token}`, {
          method: "POST",
          headers: {
            authorization: `bearer ${jwt}`,
            "apns-topic": APNS_BUNDLE_ID,
            "apns-push-type": "alert",
            "apns-priority": "10",
            "content-type": "application/json",
          },
          body: english.has(row.user_id) ? payloadEn : payloadEs,
        });
        if (response.ok) {
          sent++;
          reached.add(row.user_id);
          continue;
        }
        failed++;
        const reason = await response.text();
        if (response.status === 410 || reason.includes("BadDeviceToken") || reason.includes("Unregistered")) {
          await supabase.from("device_push_tokens").delete().eq("token", row.token);
        }
      } catch (_error) {
        failed++;
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, rows.length) }, () => worker()));
  return { sent, failed, people: reached.size };
}

/// Un aviso distinto para cada persona (ej. "te faltan $1.20 para tu
/// capuchino"). Devuelve a cuantas personas les llego.
export async function sendPersonalizedPushes(
  supabase: SupabaseClient,
  messages: { userId: string; title: string; body: string; imageUrl?: string | null; en?: { title: string; body: string } }[],
  extra: { data?: Record<string, unknown>; threadId?: string },
): Promise<{ people: number; failed: number }> {
  let people = 0;
  let failed = 0;
  for (const message of messages) {
    const result = await sendPushToUser(supabase, message.userId, {
      title: message.title,
      body: message.body,
      imageUrl: message.imageUrl,
      en: message.en,
      data: extra.data,
      threadId: extra.threadId,
    });
    if (result.sent > 0) people++;
    failed += result.failed;
  }
  return { people, failed };
}

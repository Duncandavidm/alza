import "server-only";
import { formatInt } from "./format";

// Llamadas a las Edge Functions de Supabase con el header x-admin-secret
// (ADMIN_JOB_SECRET), igual que lib/edge-functions.ts. Solo desde el
// servidor del panel: el secreto nunca llega al navegador.

export async function callAdminEdgeFunction(
  functionName: string,
  body: Record<string, unknown>
): Promise<{ ok: boolean; status: number; data: unknown }> {
  const url = process.env.SUPABASE_URL;
  const adminSecret = process.env.ADMIN_JOB_SECRET;
  if (!url || !adminSecret) {
    throw new Error("Faltan las variables de entorno SUPABASE_URL o ADMIN_JOB_SECRET");
  }

  const response = await fetch(`${url}/functions/v1/${functionName}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-admin-secret": adminSecret },
    body: JSON.stringify(body),
    cache: "no-store",
  });
  const data = await response.json().catch(() => ({}));
  return { ok: response.ok, status: response.status, data };
}

export type SendPushResult = {
  ok?: boolean;
  error?: string;
  target?: number;
  granted?: number;
  sent?: number;
  failed?: number;
  people?: number;
  skipped?: string;
  push?: { sent?: number; failed?: number; people?: number; skipped?: string };
};

/// Edge Function send-push: { push_campaign_id } o { bonus_id }.
export async function callSendPush(
  body: { push_campaign_id: string } | { bonus_id: string }
): Promise<{ ok: boolean; result: SendPushResult; error: string | null }> {
  try {
    const response = await callAdminEdgeFunction("send-push", body);
    const result = (response.data ?? {}) as SendPushResult;
    if (!response.ok || result.error) {
      return { ok: false, result, error: result.error || `La función respondió ${response.status}` };
    }
    return { ok: true, result, error: null };
  } catch (error) {
    return { ok: false, result: {}, error: error instanceof Error ? error.message : String(error) };
  }
}

/// Explicacion amable de un envio que no salio por push.
export function skippedNote(skipped: string | null | undefined): string | null {
  if (!skipped) return null;
  if (skipped === "apns_not_configured") {
    return "Las notificaciones push todavía no están configuradas (faltan las llaves de Apple en Supabase), así que no se envió ningún aviso.";
  }
  if (skipped === "no_tokens") {
    return "Nadie del segmento tiene las notificaciones activadas en su iPhone, así que no se envió ningún aviso.";
  }
  if (skipped === "bad_key") return "La llave de Apple para push no es válida: revísala en Supabase.";
  return `No se enviaron avisos (${skipped}).`;
}

/// Resumen para mostrar despues de enviar una notificacion.
export function describePushResult(result: SendPushResult): string {
  const parts = [
    `Segmento: ${formatInt(result.target ?? 0)} personas`,
    `recibieron el aviso: ${formatInt(result.people ?? 0)}`,
    `envíos a dispositivos: ${formatInt(result.sent ?? 0)}`,
  ];
  if (result.failed) parts.push(`fallidos: ${formatInt(result.failed)}`);
  const note = skippedNote(result.skipped);
  return `${parts.join(" · ")}.${note ? ` ${note}` : ""}`;
}

/// Resumen para mostrar despues de entregar un bono.
export function describeBonusResult(result: SendPushResult, notify: boolean): string {
  const push = result.push ?? { sent: result.sent, failed: result.failed, people: result.people, skipped: result.skipped };
  let text = `Entregado a ${formatInt(result.granted ?? 0)} personas.`;
  if (notify && (result.granted ?? 0) > 0) {
    const note = skippedNote(push.skipped);
    text += note
      ? ` ${note}`
      : ` Aviso push a ${formatInt(push.people ?? 0)} personas (${formatInt(push.sent ?? 0)} dispositivos${
          push.failed ? `, ${formatInt(push.failed)} fallidos` : ""
        }).`;
  }
  if ((result.granted ?? 0) === 0) text += " (Nadie nuevo en el segmento: cada persona recibe el bono una sola vez.)";
  return text;
}

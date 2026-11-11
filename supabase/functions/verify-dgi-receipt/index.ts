// Edge Function: verify-dgi-receipt
//
// "Facturas que suman" Fase 2 (verificacion real) + Fase 3 (puntos).
// Se llama de dos formas, siempre con x-admin-secret (verify_jwt: false):
//  - Al registrarse cada factura (trigger de la migracion 0049, body
//    {receipt_id}): verificacion inmediata de esa factura.
//  - Cada hora por pg_cron: reintenta las pendientes cuya ultima consulta
//    fue hace 24 h o mas.
//
// Confirmado en vivo contra dgi-fep.mef.gob.pa (ver reporte de la
// sesion, no es una suposicion): el link directo por CUFE
// (/Consultas/FacturasPorCUFE/<CUFE> — exactamente el que trae el QR
// corto y el CAFE impreso) responde 200 con la factura completa
// server-rendered en un <div id="facturaHTML">, SIN pedir reCAPTCHA (a
// diferencia del formulario de busqueda manual del sitio, que si lo
// exige via AJAX). Si el CUFE no existe, ese div llega vacio — nunca
// aparece el texto "CÓDIGO ÚNICO DE FACTURA ELECTRÓNICA" en la
// respuesta. Esa presencia/ausencia es la señal de confirmada/no
// encontrada que usa este archivo.
//
// Bonus confirmado en la misma respuesta: la factura trae "Forma de
// Pago" (ej. "Tarjeta Crédito: 84.25"). Con esto, "tarjeta en comercios
// aliados" ya NO necesita vincular tarjeta ni depender de que el
// comercio suba un reporte de ventas: si el RUC de la factura es un
// comercio aliado con oferta activa y la DGI dice que se pago con
// tarjeta, se acreditan puntos de tarjeta directo — verificado por la
// DGI, no por Visa/Mastercard ni por el comercio.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendPushToUser } from "./apns.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ADMIN_JOB_SECRET = Deno.env.get("ADMIN_JOB_SECRET")!;

const DGI_BASE = "https://dgi-fep.mef.gob.pa";
const BATCH_SIZE = 20;
// Cada corrida procesa lote tras lote hasta vaciar los pendientes, sin
// pasar de este tiempo (el limite de una Edge
// Function es mayor; esto deja margen para los avisos push del final).
const TIME_BUDGET_MS = 110_000;
// Pausa entre cada consulta — no hay razon para martillar un servidor
// del gobierno mas rapido de lo que un usuario haria a mano.
const DELAY_BETWEEN_REQUESTS_MS = 300;
const CONFIRMATION_MARKER = "CÓDIGO ÚNICO DE FACTURA ELECTRÓNICA";

const CORS_HEADERS = {
  "Access-Control-Allow-Headers": "x-admin-secret, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

/// "ALDAROVA LOGISTICS, S.A." -> "Aldarova Logistics, S.A."
function titleCase(text: string): string {
  return text
    .toLowerCase()
    .replace(/(^|[\s(/-])([a-záéíóúñ])/g, (_, prefix, letter) => prefix + letter.toUpperCase())
    .replace(/\bS\.a\./g, "S.A.");
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------------------------------------------------------------------
// Parseo del HTML de la DGI — sin libreria de DOM (no hace falta: el
// patron "ETIQUETA: <div ...>VALOR</div>" es consistente y suficiente
// para lo que necesitamos).
// ---------------------------------------------------------------------

function isConfirmed(html: string): boolean {
  return html.includes(CONFIRMATION_MARKER);
}

function extractLabeledAmount(html: string, label: string): number | null {
  const pattern = new RegExp(`${label}:\\s*<div[^>]*>\\s*([0-9]+(?:\\.[0-9]+)?)\\s*</div>`, "i");
  const match = html.match(pattern);
  return match ? Number(match[1]) : null;
}

/// "Valor Total" es el monto antes de impuestos; "TOTAL PAGADO" (dentro
/// de la seccion "Forma de Pago") es lo que de verdad se pago. Se usa
/// TOTAL PAGADO cuando existe (factura al contado con forma de pago
/// declarada) y Valor Total como respaldo (documentos sin esa seccion,
/// ej. facturas de credito/al cobro).
function extractConfirmedAmount(html: string): number | null {
  return extractLabeledAmount(html, "TOTAL PAGADO") ?? extractLabeledAmount(html, "Valor Total");
}

/// Extrae las etiquetas de forma de pago (puede haber mas de una si el
/// cliente pago mixto, ej. efectivo + tarjeta) — el texto entre el
/// marcador <kbd>Forma de Pago</kbd> y la fila TOTAL PAGADO.
function extractPaymentMethods(html: string): string[] {
  const startMarker = "<kbd>Forma de Pago</kbd>";
  const startIndex = html.indexOf(startMarker);
  if (startIndex === -1) return [];
  const endIndex = html.indexOf("TOTAL PAGADO", startIndex);
  const section = endIndex === -1 ? html.slice(startIndex) : html.slice(startIndex, endIndex);

  const methods: string[] = [];
  const rowPattern = /([A-Za-zÁÉÍÓÚáéíóúÑñ .]+?):\s*<div[^>]*>\s*[0-9]+(?:\.[0-9]+)?\s*<\/div>/g;
  let match: RegExpExecArray | null;
  while ((match = rowPattern.exec(section)) !== null) {
    methods.push(match[1].trim());
  }
  return methods;
}

function isCardPayment(paymentMethods: string[]): boolean {
  return paymentMethods.some((method) => method.toLowerCase().includes("tarjeta"));
}

function decodeEntities(text: string): string {
  return text
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)));
}

function cleanText(html: string): string {
  return decodeEntities(html.replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim();
}

/// Campos "<dt>ETIQUETA</dt><dd>VALOR</dd>" en orden de aparicion. El
/// primer NOMBRE es el del EMISOR (el comercio); el segundo, el receptor.
function extractDefinitions(html: string): { label: string; value: string }[] {
  const result: { label: string; value: string }[] = [];
  const pattern = /<dt[^>]*>([\s\S]*?)<\/dt>\s*<dd[^>]*>([\s\S]*?)<\/dd>/g;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(html)) !== null) {
    result.push({ label: cleanText(match[1]).toUpperCase(), value: cleanText(match[2]) });
  }
  return result;
}

function extractMerchantName(html: string): string | null {
  const emisorIndex = html.indexOf("EMISOR");
  const section = emisorIndex === -1 ? html : html.slice(emisorIndex);
  const name = extractDefinitions(section).find((field) => field.label === "NOMBRE")?.value;
  return name && name.length > 0 ? name.slice(0, 200) : null;
}

/// "FECHA AUTORIZACIÓN" viene como "04/11/2026 13:55:04", hora de Panama
/// (UTC-5 todo el año, sin horario de verano).
function extractAuthorizedAt(html: string): string | null {
  const raw = extractDefinitions(html).find((field) => field.label.startsWith("FECHA AUTORIZ"))?.value;
  const match = raw?.match(/(\d{2})\/(\d{2})\/(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?/);
  if (!match) return null;
  const [, day, month, year, hour, minute, second] = match;
  return `${year}-${month}-${day}T${hour}:${minute}:${second ?? "00"}-05:00`;
}

export interface ReceiptLine {
  line_no: number;
  code: string | null;
  description: string;
  quantity: number | null;
  unit_price: number | null;
  total: number | null;
}

function toNumber(value: string | undefined): number | null {
  if (!value) return null;
  const parsed = Number(value.replace(/,/g, ""));
  return Number.isFinite(parsed) ? parsed : null;
}

/// Detalle de productos: cada <tr> de la tabla "Detalle" trae celdas con
/// data-title (Linea, Código, Descripción, Cantidad, Precio, Total...).
export function extractLines(html: string): ReceiptLine[] {
  const lines: ReceiptLine[] = [];
  const rowPattern = /<tr>([\s\S]*?)<\/tr>/g;
  let row: RegExpExecArray | null;
  while ((row = rowPattern.exec(html)) !== null) {
    if (!row[1].includes('data-title="Descripción"')) continue;
    const cells: Record<string, string> = {};
    const cellPattern = /<td[^>]*data-title="([^"]+)"[^>]*>([\s\S]*?)<\/td>/g;
    let cell: RegExpExecArray | null;
    while ((cell = cellPattern.exec(row[1])) !== null) {
      cells[cell[1]] = cleanText(cell[2]);
    }
    const description = cells["Descripción"];
    if (!description) continue;
    lines.push({
      line_no: toNumber(cells["Linea"]) ?? lines.length + 1,
      code: cells["Código"] || null,
      description: description.slice(0, 300),
      quantity: toNumber(cells["Cantidad"]),
      unit_price: toNumber(cells["Precio"]),
      total: toNumber(cells["Total"]),
    });
    if (lines.length >= 200) break;
  }
  return lines;
}

// ---------------------------------------------------------------------
// Reglas / topes (points_rules + app_config, ver migraciones 0023 y
// 0029 — configurable sin desplegar nada).
// ---------------------------------------------------------------------

async function getRule(
  supabase: ReturnType<typeof createClient>,
  source: string,
  key: string,
  fallback: number,
): Promise<number> {
  const { data } = await supabase
    .from("points_rules")
    .select("value")
    .eq("source", source)
    .eq("key", key)
    .maybeSingle();
  const value = data?.value;
  return typeof value === "number" ? value : fallback;
}

async function getConfig(
  supabase: ReturnType<typeof createClient>,
  key: string,
): Promise<unknown> {
  const { data } = await supabase.from("app_config").select("value").eq("key", key).maybeSingle();
  return data?.value;
}

async function pointsAlreadyToday(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  source: string,
  occurredAt: string,
): Promise<number> {
  const dayStart = new Date(occurredAt);
  dayStart.setUTCHours(0, 0, 0, 0);
  const dayEnd = new Date(dayStart);
  dayEnd.setUTCDate(dayEnd.getUTCDate() + 1);

  const { data } = await supabase
    .from("points_ledger")
    .select("points")
    .eq("user_id", userId)
    .eq("source", source)
    .gte("occurred_at", dayStart.toISOString())
    .lt("occurred_at", dayEnd.toISOString());
  return (data ?? []).reduce((sum: number, row: { points: number }) => sum + row.points, 0);
}

// ---------------------------------------------------------------------
// Bono de "tarjeta en comercios aliados" — reusa partner_merchants/
// partner_merchant_offers (migracion 0024), pero ya NO linked_cards: el
// pago con tarjeta lo confirma la propia DGI en la factura, no hace
// falta vincular ninguna tarjeta.
// ---------------------------------------------------------------------

async function awardCardBonusIfApplicable(
  supabase: ReturnType<typeof createClient>,
  receipt: { id: string; user_id: string; ruc: string; cufe: string },
  amount: number,
  paymentMethods: string[],
  occurredAt: string,
): Promise<number> {
  if (!isCardPayment(paymentMethods)) return 0;

  const { data: merchant } = await supabase
    .from("partner_merchants")
    .select("id, name, status")
    .eq("ruc", receipt.ruc)
    .eq("status", "active")
    .maybeSingle();
  if (!merchant) return 0;

  const { data: offer } = await supabase
    .from("partner_merchant_offers")
    .select("*")
    .eq("merchant_id", merchant.id)
    .eq("status", "active")
    .lte("starts_at", occurredAt)
    .or(`ends_at.is.null,ends_at.gte.${occurredAt}`)
    .order("starts_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!offer) return 0;

  if (offer.min_amount && amount < Number(offer.min_amount)) return 0;

  const rawPoints = offer.offer_type === "percent" ? amount * Number(offer.value) : Number(offer.value);
  const points = Math.max(0, Math.floor(rawPoints));
  if (points === 0) return 0;

  if (offer.budget_total_points !== null && offer.budget_spent_points + points > offer.budget_total_points) {
    await supabase.from("partner_merchant_offers").update({ status: "budget_exhausted" }).eq("id", offer.id);
    return 0;
  }

  const dailyCap = await getRule(supabase, "tarjeta", "daily_cap_points_per_user", Number.POSITIVE_INFINITY);
  const alreadyToday = await pointsAlreadyToday(supabase, receipt.user_id, "tarjeta", occurredAt);
  if (alreadyToday + points > dailyCap) return 0;

  await supabase.rpc("award_points", {
    p_user_id: receipt.user_id,
    p_source: "tarjeta",
    p_external_ref: `factura:${receipt.cufe}:tarjeta`,
    p_points: points,
    p_status: "confirmado",
    p_occurred_at: occurredAt,
    p_metadata: { cufe: receipt.cufe, merchant: merchant.name, offerId: offer.id, viaFactura: true },
  });

  await supabase
    .from("partner_merchant_offers")
    .update({ budget_spent_points: offer.budget_spent_points + points })
    .eq("id", offer.id);

  return points;
}

// ---------------------------------------------------------------------
// Reconciliacion de una factura pendiente.
// ---------------------------------------------------------------------

interface PendingReceipt {
  id: string;
  user_id: string;
  cufe: string;
  ruc: string;
  scanned_at: string;
  dgi_check_count: number;
}

interface ReceiptResult {
  /// Puntos sumados en esta corrida por esta factura (factura + bono).
  points: number;
  merchantName: string | null;
  /// true si el cashback quedo retenido porque los ingresos registrados no
  /// respaldan la compra (trigger de la migracion 0045).
  held: boolean;
}

async function processReceipt(
  supabase: ReturnType<typeof createClient>,
  receipt: PendingReceipt,
  pointsPerDollar: number,
  dailyCapFactura: number,
  expireAfterDays: number,
): Promise<ReceiptResult | null> {
  const now = new Date();
  let response: Response;
  try {
    response = await fetch(`${DGI_BASE}/Consultas/FacturasPorCUFE/${receipt.cufe}`, {
      signal: AbortSignal.timeout(15_000),
    });
  } catch {
    return null;
  }
  if (!response.ok) {
    // Fallo transitorio (servidor caido, etc.) — no se cuenta como un
    // intento real, se reintenta en la proxima corrida.
    return null;
  }
  const html = await response.text();

  if (!isConfirmed(html)) {
    const scannedAt = new Date(receipt.scanned_at);
    const daysSinceScanned = (now.getTime() - scannedAt.getTime()) / (1000 * 60 * 60 * 24);
    const newStatus = daysSinceScanned >= expireAfterDays ? "expirada" : "pendiente";
    await supabase
      .from("dgi_receipts")
      .update({
        status: newStatus,
        dgi_checked_at: now.toISOString(),
        dgi_check_count: receipt.dgi_check_count + 1,
      })
      .eq("id", receipt.id);
    return null;
  }

  const amount = extractConfirmedAmount(html);
  const paymentMethods = extractPaymentMethods(html);
  const merchantName = extractMerchantName(html);
  const authorizedAt = extractAuthorizedAt(html);
  const lines = extractLines(html);

  await supabase
    .from("dgi_receipts")
    .update({
      status: "confirmada",
      confirmed_amount: amount,
      payment_method: paymentMethods.length > 0 ? paymentMethods.join(", ") : null,
      merchant_name: merchantName,
      authorized_at: authorizedAt,
      dgi_checked_at: now.toISOString(),
      dgi_check_count: receipt.dgi_check_count + 1,
    })
    .eq("id", receipt.id);

  // Detalle de productos (estudio de mercado) y comercio para el catalogo
  // RUC -> nombre que autocompleta futuros escaneos. Si falla, no frena
  // los puntos.
  if (lines.length > 0) {
    const { error: linesError } = await supabase.from("dgi_receipt_items").upsert(
      lines.map((line) => ({ ...line, receipt_id: receipt.id, user_id: receipt.user_id })),
      { onConflict: "receipt_id,line_no" },
    );
    if (linesError) console.error("dgi_receipt_items", linesError.message);
  }
  if (merchantName) {
    await supabase.from("merchants").upsert(
      { ruc: receipt.ruc, name: merchantName },
      { onConflict: "ruc", ignoreDuplicates: true },
    );
  }

  if (amount === null || amount <= 0) return { points: 0, merchantName, held: false };

  let awarded = 0;
  const points = Math.max(0, Math.floor(amount * pointsPerDollar));
  if (points > 0) {
    const alreadyToday = await pointsAlreadyToday(supabase, receipt.user_id, "factura", receipt.scanned_at);
    if (alreadyToday + points <= dailyCapFactura) {
      await supabase.rpc("award_points", {
        p_user_id: receipt.user_id,
        p_source: "factura",
        p_external_ref: `factura:${receipt.cufe}`,
        p_points: points,
        p_status: "confirmado",
        p_occurred_at: receipt.scanned_at,
        p_metadata: { cufe: receipt.cufe, confirmedAmount: amount, paymentMethod: paymentMethods },
      });
      awarded += points;
    }
  }

  awarded += await awardCardBonusIfApplicable(
    supabase,
    { id: receipt.id, user_id: receipt.user_id, ruc: receipt.ruc, cufe: receipt.cufe },
    amount,
    paymentMethods,
    receipt.scanned_at,
  );

  const { data: after } = await supabase
    .from("dgi_receipts").select("cashback_status").eq("id", receipt.id).maybeSingle();
  return { points: awarded, merchantName, held: after?.cashback_status === "sin_ingreso" };
}

type UserSummary = { points: number; held: number; receipts: number; merchants: Set<string> };

/// Un solo aviso push por persona con lo que se confirmo.
async function notifyUser(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  entry: UserSummary,
): Promise<number> {
  if (entry.points <= 0 && entry.held <= 0) return 0;
  const merchantText = entry.receipts === 1 && entry.merchants.size === 1
    ? `Tu factura de ${titleCase([...entry.merchants][0])} fue verificada.`
    : `${entry.receipts} facturas fueron verificadas.`;
  // 1 punto = US$0.01 de cashback.
  const money = (points: number) => "$" + (points / 100).toFixed(2);
  const message = entry.points > 0
    ? {
      title: `¡Ganaste ${money(entry.points)} de cashback! 💸`,
      body: entry.held > 0
        ? `${merchantText} Tienes ${money(entry.held)} más pendientes: registra tus ingresos para recibirlos.`
        : `${merchantText} Úsalo en los comercios aliados de MonAvi.`,
      data: { screen: "points" },
    }
    : {
      title: `Tienes ${money(entry.held)} de cashback pendiente`,
      body: `${merchantText} Para recibirlo, registra tus ingresos del mes en MonAvi: el cashback se respalda con lo que ganas.`,
      data: { screen: "home" },
    };
  const result = await sendPushToUser(supabase, userId, message);
  return result.sent;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  if (req.headers.get("x-admin-secret") !== ADMIN_JOB_SECRET) {
    return jsonResponse({ error: "No autorizado" }, 401);
  }

  try {
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const verificationEnabled = await getConfig(supabase, "dgi_verification_enabled");
    if (verificationEnabled !== true) {
      return jsonResponse({ skipped: true, reason: "dgi_verification_enabled esta en false" });
    }

    const pointsPerDollar = await getRule(supabase, "factura", "points_per_dollar", 1);
    const dailyCapFactura = await getRule(supabase, "factura", "daily_cap_points_per_user", 300);
    const expireAfterDays = Number((await getConfig(supabase, "dgi_verification_expire_after_days")) ?? 7);

    // Modo inmediato: el trigger de dgi_receipts (migracion 0049) llama
    // con {receipt_id} apenas se registra la factura. Se consulta a la DGI
    // en ese momento; si ya esta publicada, el cashback se suma de una vez.
    let body: { receipt_id?: string } = {};
    try { body = await req.json(); } catch { /* corrida diaria sin body */ }
    if (body.receipt_id) {
      const { data: row } = await supabase
        .from("dgi_receipts")
        .select("id, user_id, cufe, ruc, scanned_at, dgi_check_count")
        .eq("id", body.receipt_id).eq("status", "pendiente").maybeSingle();
      if (!row) return jsonResponse({ immediate: true, skipped: "no pendiente" });
      const result = await processReceipt(supabase, row as PendingReceipt, pointsPerDollar, dailyCapFactura, expireAfterDays);
      let pushesSent = 0;
      if (result) {
        pushesSent = await notifyUser(supabase, row.user_id as string, {
          points: result.held ? 0 : result.points,
          held: result.held ? result.points : 0,
          receipts: 1,
          merchants: new Set(result.merchantName ? [result.merchantName] : []),
        });
      }
      return jsonResponse({ immediate: true, confirmed: result !== null, pushesSent });
    }

    // Corrida periodica (cada hora): solo las facturas cuya ultima consulta
    // fue hace 24 horas o mas. Asi, si al escanear la DGI aun no la tenia
    // publicada, se vuelve a consultar ~24 h despues (y luego cada 24 h
    // hasta confirmarla o vencer a los dgi_verification_expire_after_days).
    const recheckBefore = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

    const startedAt = Date.now();
    const seen = new Set<string>();
    let fetched = 0;
    let processed = 0;
    let confirmed = 0;
    const errors: string[] = [];
    // Por usuario: puntos sumados y facturas confirmadas en esta corrida,
    // para mandar UN solo aviso push por persona al final.
    const perUser = new Map<string, UserSummary>();

    while (Date.now() - startedAt < TIME_BUDGET_MS) {
      const { data, error } = await supabase
        .from("dgi_receipts")
        .select("id, user_id, cufe, ruc, scanned_at, dgi_check_count")
        .eq("status", "pendiente")
        .or(`dgi_checked_at.is.null,dgi_checked_at.lte.${recheckBefore}`)
        .order("dgi_checked_at", { ascending: true, nullsFirst: true })
        .limit(Math.min(BATCH_SIZE + seen.size, 1000));
      if (error) throw error;

      // Las que siguen pendientes tras revisarlas en esta corrida vuelven a
      // salir en la consulta: se saltan para no revisarlas dos veces.
      const pending: PendingReceipt[] = (data ?? [])
        .filter((row: Record<string, unknown>) => !seen.has(row.id as string))
        .map((row: Record<string, unknown>) => ({
          id: row.id as string,
          user_id: row.user_id as string,
          cufe: row.cufe as string,
          ruc: row.ruc as string,
          scanned_at: row.scanned_at as string,
          dgi_check_count: row.dgi_check_count as number,
        }));
      if (pending.length === 0) break;
      fetched += pending.length;

      for (const receipt of pending) {
        if (Date.now() - startedAt >= TIME_BUDGET_MS) break;
        seen.add(receipt.id);
        try {
          const result = await processReceipt(supabase, receipt, pointsPerDollar, dailyCapFactura, expireAfterDays);
          processed++;
          if (result) {
            confirmed++;
            const entry = perUser.get(receipt.user_id) ?? { points: 0, held: 0, receipts: 0, merchants: new Set<string>() };
            if (result.held) entry.held += result.points;
            else entry.points += result.points;
            entry.receipts += 1;
            if (result.merchantName) entry.merchants.add(result.merchantName);
            perUser.set(receipt.user_id, entry);
          }
        } catch (recordError) {
          errors.push(`${receipt.cufe}: ${String(recordError)}`);
        }
        await sleep(DELAY_BETWEEN_REQUESTS_MS);
      }
    }

    let pushesSent = 0;
    for (const [userId, entry] of perUser) {
      pushesSent += await notifyUser(supabase, userId, entry);
    }

    return jsonResponse({ fetched, processed, confirmed, pushesSent, errors });
  } catch (error) {
    console.error(error);
    return jsonResponse({ error: String(error) }, 500);
  }
});

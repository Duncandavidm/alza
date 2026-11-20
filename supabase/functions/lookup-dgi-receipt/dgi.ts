// Lectura del HTML de la consulta publica de facturas electronicas
// (copia de las funciones de verify-dgi-receipt/index.ts; si cambia el
// formato de la pagina, actualizar ambos).

export const CONFIRMATION_MARKER = "CÓDIGO ÚNICO DE FACTURA ELECTRÓNICA";

export function titleCase(text: string): string {
  return text
    .toLowerCase()
    .replace(/(^|[\s(/-])([a-záéíóúñ])/g, (_, prefix, letter) => prefix + letter.toUpperCase())
    .replace(/\bS\.a\./g, "S.A.");
}

// ---------------------------------------------------------------------
// Parseo del HTML de la DGI — sin libreria de DOM (no hace falta: el
// patron "ETIQUETA: <div ...>VALOR</div>" es consistente y suficiente
// para lo que necesitamos).
// ---------------------------------------------------------------------

export function isConfirmed(html: string): boolean {
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
export function extractConfirmedAmount(html: string): number | null {
  return extractLabeledAmount(html, "TOTAL PAGADO") ?? extractLabeledAmount(html, "Valor Total");
}

/// Extrae las etiquetas de forma de pago (puede haber mas de una si el
/// cliente pago mixto, ej. efectivo + tarjeta) — el texto entre el
/// marcador <kbd>Forma de Pago</kbd> y la fila TOTAL PAGADO.
export function extractPaymentMethods(html: string): string[] {
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

export function extractMerchantName(html: string): string | null {
  const emisorIndex = html.indexOf("EMISOR");
  const section = emisorIndex === -1 ? html : html.slice(emisorIndex);
  const name = extractDefinitions(section).find((field) => field.label === "NOMBRE")?.value;
  return name && name.length > 0 ? name.slice(0, 200) : null;
}

/// "FECHA AUTORIZACIÓN" viene como "04/11/2026 13:55:04", hora de Panama
/// (UTC-5 todo el año, sin horario de verano).
export function extractAuthorizedAt(html: string): string | null {
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


// Validaciones compartidas (servidor) para formularios del panel y de la
// landing publica. Sin dependencias.

export function text(formData: FormData, key: string, maxLength = 200): string {
  const value = String(formData.get(key) ?? "").trim();
  return value.slice(0, maxLength);
}

export function optionalText(formData: FormData, key: string, maxLength = 200): string | null {
  const value = text(formData, key, maxLength);
  return value.length > 0 ? value : null;
}

/// Devuelve la URL normalizada si es un enlace http(s) valido, o null.
export function parseHttpUrl(raw: string): string | null {
  const value = raw.trim();
  if (!value) return null;
  try {
    const url = new URL(value);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    if (!url.hostname.includes(".")) return null;
    return url.toString();
  } catch {
    return null;
  }
}

/// Enlaces de Google Maps aceptados: maps.app.goo.gl, goo.gl/maps,
/// google.com/maps (y dominios regionales como google.com.pa/maps) y
/// maps.google.com. Devuelve { url } normalizada, { url: null } si vino
/// vacio, o { error } si no es un enlace valido.
export function parseMapsUrl(raw: string): { url: string | null; error?: string } {
  if (!raw.trim()) return { url: null };
  const normalized = parseHttpUrl(raw);
  if (!normalized || normalized.length > 500) {
    return { url: null, error: "El enlace de Google Maps debe ser una URL que empiece con http:// o https://." };
  }
  const url = new URL(normalized);
  const host = url.hostname.toLowerCase().replace(/^www\./, "");
  const isGoogleMaps =
    host === "maps.app.goo.gl" ||
    (host === "goo.gl" && url.pathname.startsWith("/maps")) ||
    /^maps\.google\.[a-z.]+$/.test(host) ||
    (/^google\.[a-z.]+$/.test(host) && url.pathname.startsWith("/maps"));
  if (!isGoogleMaps) {
    return {
      url: null,
      error: "Usa un enlace de Google Maps (por ejemplo https://maps.app.goo.gl/… o https://www.google.com/maps/…).",
    };
  }
  return { url: normalized };
}

export function isValidEmail(value: string): boolean {
  return value.length <= 160 && /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value);
}

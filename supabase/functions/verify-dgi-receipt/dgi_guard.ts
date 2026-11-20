// Consultas a la DGI con freno (migracion 0067). Se copia igual en
// lookup-dgi-receipt y verify-dgi-receipt al desplegar.
//
// - Antes de cada consulta se pide permiso a dgi_acquire(): tope global
//   por minuto (app_config.dgi_max_requests_per_minute, 30 por defecto) y
//   pausa automatica si la DGI viene fallando. Sin permiso no se consulta:
//   la factura queda pendiente y se revisa en la proxima corrida.
// - Cada respuesta se reporta con dgi_report(). Una respuesta 200 que no es
//   la pagina de la DGI (captcha, bloqueo, mantenimiento) cuenta como
//   "blocked" y NO como "factura no encontrada": asi un bloqueo nunca hace
//   vencer facturas reales.
// - La pagina confirmada que se lee al escanear se guarda unos minutos
//   (dgi_page_cache) para que la verificacion inmediata no vuelva a
//   consultar la misma factura segundos despues.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const DGI_BASE = "https://dgi-fep.mef.gob.pa";
const USER_AGENT = "MonAvi/1.0 (+https://monavi.maday.app)";
const CONFIRMATION_MARKER = "CÓDIGO ÚNICO DE FACTURA ELECTRÓNICA";
// La pagina de busqueda de la DGI (la que sale si la factura aun no esta).
const SEARCH_PAGE_MARKER = /Facturas\s+Por\s+CUFE/i;
const CACHE_MAX_AGE_MS = 30 * 60 * 1000;

export type DgiOutcome = "ok" | "not_found" | "blocked" | "error";

export type DgiPage =
  | { kind: "confirmed"; html: string }
  | { kind: "not_found"; html: string }
  | { kind: "unavailable"; reason: "busy" | "blocked" | "error" };

export function classifyDgiPage(status: number, html: string): DgiOutcome {
  if (status === 403 || status === 429) return "blocked";
  if (status >= 400) return "error";
  if (html.includes(CONFIRMATION_MARKER)) return "ok";
  if (SEARCH_PAGE_MARKER.test(html)) return "not_found";
  return "blocked";
}

export async function fetchDgiPage(
  supabase: SupabaseClient,
  cufe: string,
  source: string,
  opts: { timeoutMs: number; useCache?: boolean; saveCache?: boolean },
): Promise<DgiPage> {
  if (opts.useCache) {
    const { data: cached } = await supabase
      .from("dgi_page_cache").select("html, fetched_at").eq("cufe", cufe).maybeSingle();
    if (cached) {
      await supabase.from("dgi_page_cache").delete().eq("cufe", cufe);
      if (Date.now() - Date.parse(cached.fetched_at as string) < CACHE_MAX_AGE_MS) {
        return { kind: "confirmed", html: cached.html as string };
      }
    }
  }

  const { data: ticket, error: acquireError } = await supabase.rpc("dgi_acquire", { p_source: source });
  if (acquireError) {
    console.error("dgi_acquire", acquireError.message);
    return { kind: "unavailable", reason: "error" };
  }
  if (ticket === null || ticket === undefined) return { kind: "unavailable", reason: "busy" };

  let outcome: DgiOutcome = "error";
  let html = "";
  try {
    const response = await fetch(`${DGI_BASE}/Consultas/FacturasPorCUFE/${encodeURIComponent(cufe)}`, {
      headers: { "User-Agent": USER_AGENT, Accept: "text/html" },
      signal: AbortSignal.timeout(opts.timeoutMs),
    });
    html = await response.text();
    outcome = classifyDgiPage(response.status, html);
  } catch {
    outcome = "error";
  }

  const { error: reportError } = await supabase.rpc("dgi_report", { p_id: ticket, p_outcome: outcome });
  if (reportError) console.error("dgi_report", reportError.message);

  if (outcome === "ok") {
    if (opts.saveCache) {
      await supabase.from("dgi_page_cache").upsert({ cufe, html, fetched_at: new Date().toISOString() });
    }
    return { kind: "confirmed", html };
  }
  if (outcome === "not_found") return { kind: "not_found", html };
  return { kind: "unavailable", reason: outcome };
}

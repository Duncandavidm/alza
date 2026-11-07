// Edge Function: lookup-dgi-receipt
//
// La app la llama justo al escanear el QR de una factura electronica:
// consulta UNA vez la pagina publica de la factura (lo mismo que haria la
// persona abriendo el enlace del QR) y devuelve comercio, monto, fecha,
// forma de pago, productos y la categoria sugerida, para llenar el gasto
// solo. No guarda nada: el registro y el cashback siguen su camino normal
// (la factura queda pendiente y el job diario la verifica y acredita).
//
// Tambien dice si los ingresos registrados alcanzan para respaldar el
// cashback de esta compra (ver migracion 0045), para avisarle a la persona.
//
// verify_jwt: true. Limite: 30 consultas cada 10 minutos por usuario.

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  extractAuthorizedAt,
  extractConfirmedAmount,
  extractLines,
  extractMerchantName,
  extractPaymentMethods,
  isConfirmed,
  titleCase,
} from "./dgi.ts";
import { categorize } from "./categorize.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DGI_BASE = "https://dgi-fep.mef.gob.pa";

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
    return typeof payload.sub === "string" && payload.role === "authenticated" ? payload.sub : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });

  const userId = getVerifiedUserId(req);
  if (!userId) return jsonResponse({ error: "No autorizado" }, 401);

  let cufe = "";
  try {
    const body = await req.json();
    cufe = String(body?.cufe ?? "").trim().toUpperCase();
  } catch {
    return jsonResponse({ error: "JSON invalido" }, 400);
  }
  if (!/^[A-Z0-9-]{20,120}$/.test(cufe)) {
    return jsonResponse({ error: "Código de factura inválido" }, 400);
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: allowed, error: limitError } = await supabase.rpc("check_and_increment_rate_limit", {
    p_user_id: userId,
    p_function_name: "lookup-dgi-receipt",
    p_max_requests: 30,
    p_window_seconds: 600,
  });
  if (!limitError && allowed === false) {
    return jsonResponse({ error: "Demasiadas consultas seguidas. Espera unos minutos." }, 429);
  }

  // Cada factura solo se registra una vez en toda la app.
  const { data: existing } = await supabase
    .from("dgi_receipts").select("user_id").eq("cufe", cufe).maybeSingle();
  if (existing) {
    return jsonResponse({
      status: "duplicada",
      mine: existing.user_id === userId,
      message: existing.user_id === userId
        ? "Ya registraste esta factura."
        : "Esta factura ya fue registrada por otra cuenta.",
    });
  }

  // Ingresos registrados vs compras con cashback (ultimos 30-35 dias).
  const since35 = new Date(Date.now() - 35 * 86_400_000).toISOString();
  const since30 = new Date(Date.now() - 30 * 86_400_000).toISOString();
  const [{ data: incomes }, { data: backed }] = await Promise.all([
    supabase.from("transactions").select("amount").eq("user_id", userId).eq("movement_type", "ingreso")
      .gt("amount", 0).gte("occurred_at", since35),
    supabase.from("dgi_receipts").select("confirmed_amount").eq("user_id", userId)
      .eq("cashback_status", "acreditado").gte("scanned_at", since30),
  ]);
  const incomeTotal = (incomes ?? []).reduce((sum: number, row: { amount: number }) => sum + Number(row.amount), 0);
  const backedTotal = (backed ?? []).reduce(
    (sum: number, row: { confirmed_amount: number | null }) => sum + Number(row.confirmed_amount ?? 0), 0);

  let html: string;
  try {
    const response = await fetch(`${DGI_BASE}/Consultas/FacturasPorCUFE/${cufe}`, {
      signal: AbortSignal.timeout(12_000),
    });
    if (!response.ok) throw new Error(String(response.status));
    html = await response.text();
  } catch {
    return jsonResponse({ status: "no_disponible", income_total: incomeTotal, backed_total: backedTotal });
  }

  if (!isConfirmed(html)) {
    // Aun no aparece (puede tardar): la app deja escribir el monto a mano.
    return jsonResponse({ status: "pendiente", income_total: incomeTotal, backed_total: backedTotal });
  }

  const amount = extractConfirmedAmount(html);
  const merchantRaw = extractMerchantName(html);
  const merchantName = merchantRaw ? titleCase(merchantRaw) : null;
  const items = extractLines(html).map((line) => ({
    description: line.description,
    quantity: line.quantity,
    total: line.total,
  }));
  const categorization = categorize(merchantName, items, amount);

  return jsonResponse({
    status: "confirmada",
    merchant_name: merchantName,
    amount,
    authorized_at: extractAuthorizedAt(html),
    payment_methods: extractPaymentMethods(html),
    items: categorization.lines.slice(0, 60),
    suggested_category: categorization.suggested,
    breakdown: categorization.breakdown,
    income_total: Math.round(incomeTotal * 100) / 100,
    backed_total: Math.round(backedTotal * 100) / 100,
    income_backs_purchase: amount !== null && backedTotal + amount <= incomeTotal,
  });
});

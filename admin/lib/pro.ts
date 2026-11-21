import { supabaseAdmin } from "@/lib/supabase-admin";
import { LIFETIME_PRODUCT_ID } from "@/lib/customer-accounts";

export const PRO_MONTHLY_ID = "app.monavi.sub.pro";
export const PRO_ANNUAL_ID = "app.monavi.sub.pro.annual";
/// La prueba gratis de Apple dura 1 semana (MonAvi.storekit).
const TRIAL_DAYS = 7;

export type ProPrices = { monthly: number; annual: number; commissionPct: number };
export const DEFAULT_PRO_PRICES: ProPrices = { monthly: 7.99, annual: 74.99, commissionPct: 15 };

export type ProBreakdown = {
  monthly: number;
  annual: number;
  /// Pagan por Apple pero estan en su primera semana: casi seguro en la
  /// prueba gratis (Apple no le avisa al servidor si es prueba).
  trial: number;
  lifetime: number;
  /// Pro activo por otra via (codigos, productos viejos).
  other: number;
  paying: number;
  totalPro: number;
  grossMonthly: number;
  netMonthly: number;
  prices: ProPrices;
};

type SubRow = {
  product_id: string | null;
  status: string | null;
  expires_at: string | null;
  apple_original_transaction_id: string | null;
  created_at: string | null;
};

const num = (value: unknown, fallback: number) => {
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
};

export async function fetchProPrices(): Promise<ProPrices> {
  const { data } = await supabaseAdmin()
    .from("app_config")
    .select("key, value")
    .in("key", ["pro_price_monthly_usd", "pro_price_annual_usd", "apple_commission_pct"]);
  const map = new Map((data ?? []).map((row: { key: string; value: unknown }) => [row.key, row.value]));
  return {
    monthly: num(map.get("pro_price_monthly_usd"), DEFAULT_PRO_PRICES.monthly),
    annual: num(map.get("pro_price_annual_usd"), DEFAULT_PRO_PRICES.annual),
    commissionPct: Math.min(num(map.get("apple_commission_pct"), DEFAULT_PRO_PRICES.commissionPct), 100),
  };
}

/// Suscriptores Pro separados: pagan (mensual / anual), en semana gratis,
/// de por vida (regalados desde el panel) y otros; mas el ingreso estimado
/// al mes (anual / 12) antes y despues de la comision de Apple.
export async function fetchProBreakdown(now = new Date()): Promise<ProBreakdown> {
  const [{ data }, prices] = await Promise.all([
    supabaseAdmin()
      .from("subscriptions")
      .select("product_id, status, expires_at, apple_original_transaction_id, created_at")
      .eq("status", "active")
      .limit(20000),
    fetchProPrices(),
  ]);
  const trialCutoff = now.getTime() - TRIAL_DAYS * 86_400_000;
  const result = { monthly: 0, annual: 0, trial: 0, lifetime: 0, other: 0 };

  for (const row of (data ?? []) as SubRow[]) {
    if (row.expires_at && new Date(row.expires_at).getTime() <= now.getTime()) continue;
    if (row.product_id === LIFETIME_PRODUCT_ID) {
      result.lifetime += 1;
      continue;
    }
    const isApple = Boolean(row.apple_original_transaction_id);
    const isMonthly = row.product_id === PRO_MONTHLY_ID;
    const isAnnual = row.product_id === PRO_ANNUAL_ID;
    if (!isApple || (!isMonthly && !isAnnual)) {
      result.other += 1;
      continue;
    }
    if (row.created_at && new Date(row.created_at).getTime() > trialCutoff) {
      result.trial += 1;
      continue;
    }
    if (isMonthly) result.monthly += 1;
    else result.annual += 1;
  }

  const grossMonthly = result.monthly * prices.monthly + (result.annual * prices.annual) / 12;
  const paying = result.monthly + result.annual;
  return {
    ...result,
    paying,
    totalPro: paying + result.trial + result.lifetime + result.other,
    grossMonthly: Math.round(grossMonthly * 100) / 100,
    netMonthly: Math.round(grossMonthly * (1 - prices.commissionPct / 100) * 100) / 100,
    prices,
  };
}

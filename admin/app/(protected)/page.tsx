import Link from "next/link";
import { supabaseAdmin } from "@/lib/supabase-admin";

async function countRows(table: string, filters: Record<string, string>): Promise<number> {
  const supabase = supabaseAdmin();
  let query = supabase.from(table).select("id", { count: "exact", head: true });
  for (const [column, value] of Object.entries(filters)) {
    query = query.eq(column, value);
  }
  const { count } = await query;
  return count ?? 0;
}

export default async function DashboardPage() {
  const [pendingCard, ambiguousCard, pendingBank, budgetExhausted, activeMerchants, activeBanks] = await Promise.all([
    countRows("card_transactions", { match_status: "pending_match" }),
    countRows("card_transactions", { match_status: "ambiguous" }),
    countRows("savings_bank_reports", { match_status: "pending_match" }),
    countRows("partner_merchant_offers", { status: "budget_exhausted" }),
    countRows("partner_merchants", { status: "active" }),
    countRows("bank_partners", { status: "active" }),
  ]);

  return (
    <>
      <h1>Resumen</h1>
      <div className="grid-form">
        <StatCard label="Comercios activos" value={activeMerchants} href="/merchants" />
        <StatCard label="Bancos activos" value={activeBanks} href="/bank-partners" />
        <StatCard label="Compras de tarjeta sin procesar" value={pendingCard} href="/card-reports" />
        <StatCard label="Compras ambiguas (revisar)" value={ambiguousCard} href="/alerts" warn={ambiguousCard > 0} />
        <StatCard label="Reportes de banco sin procesar" value={pendingBank} href="/bank-reports" />
        <StatCard label="Ofertas con presupuesto agotado" value={budgetExhausted} href="/alerts" warn={budgetExhausted > 0} />
      </div>
    </>
  );
}

function StatCard({ label, value, href, warn }: { label: string; value: number; href: string; warn?: boolean }) {
  return (
    <Link href={href} className="card" style={{ display: "block" }}>
      <div className="text-dim">{label}</div>
      <div style={{ fontSize: 28, fontWeight: 700, color: warn ? "var(--warning)" : "var(--text)" }}>{value}</div>
    </Link>
  );
}

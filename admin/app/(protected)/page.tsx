import Link from "next/link";
import { headers } from "next/headers";
import { supabaseAdmin } from "@/lib/supabase-admin";
import CopyButton from "@/components/CopyButton";

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
  const [
    pendingCard,
    ambiguousCard,
    pendingBank,
    budgetExhausted,
    activeMerchants,
    activeBanks,
    pendingDgi,
    newApplications,
    pendingRedemptions,
    activeRewards,
  ] = await Promise.all([
    countRows("card_transactions", { match_status: "pending_match" }),
    countRows("card_transactions", { match_status: "ambiguous" }),
    countRows("savings_bank_reports", { match_status: "pending_match" }),
    countRows("partner_merchant_offers", { status: "budget_exhausted" }),
    countRows("partner_merchants", { status: "active" }),
    countRows("bank_partners", { status: "active" }),
    countRows("dgi_receipts", { status: "pendiente" }),
    countRows("merchant_applications", { status: "nueva" }),
    countRows("reward_redemptions", { status: "emitido" }),
    countRows("reward_items", { status: "active" }),
  ]);

  const headerList = await headers();
  const host = headerList.get("x-forwarded-host") ?? headerList.get("host") ?? "monavi.vercel.app";
  const protocol = headerList.get("x-forwarded-proto") ?? (host.startsWith("localhost") ? "http" : "https");
  const landingUrl = `${protocol}://${host}/aliados`;

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
        <StatCard label="Facturas DGI pendientes" value={pendingDgi} href="/dgi-verification" />
        <StatCard label="Solicitudes de comercios nuevas" value={newApplications} href="/applications?status=nueva" warn={newApplications > 0} />
        <StatCard label="Productos canjeables activos" value={activeRewards} href="/merchants" />
        <StatCard label="Canjes por entregar" value={pendingRedemptions} href="/redemptions?status=emitido" />
      </div>

      <div className="card" style={{ marginTop: 16 }}>
        <h3>Landing para comercios aliados</h3>
        <p className="text-dim">
          Página pública (no requiere clave) donde los negocios piden ser aliados de MonAvi. Las solicitudes llegan a{" "}
          <Link href="/applications">Solicitudes</Link>.
        </p>
        <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
          <code>{landingUrl}</code>
          <CopyButton value={landingUrl} />
          <a href="/aliados" target="_blank" rel="noreferrer">
            Abrir
          </a>
        </div>
      </div>

      <div className="card">
        <h3>Estudio de mercado</h3>
        <p className="text-dim">
          Reporte agregado y anónimo del comportamiento de compra (general o para los clientes de un aliado), listo para
          imprimir o descargar en CSV. <Link href="/insights">Abrir estudio de mercado</Link>
        </p>
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

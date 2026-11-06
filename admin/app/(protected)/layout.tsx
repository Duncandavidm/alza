import Link from "next/link";
import { logout } from "../login/actions";
import { supabaseAdmin } from "@/lib/supabase-admin";

// Panel interno: siempre datos frescos de la base. Sin esto, Next
// prerenderiza en el build las paginas sin searchParams (p. ej.
// /merchants, /alerts) y mostraria datos del momento del deploy.
export const dynamic = "force-dynamic";

async function countNewApplications(): Promise<number> {
  try {
    const { count } = await supabaseAdmin()
      .from("merchant_applications")
      .select("id", { count: "exact", head: true })
      .eq("status", "nueva");
    return count ?? 0;
  } catch {
    return 0;
  }
}

export default async function ProtectedLayout({ children }: { children: React.ReactNode }) {
  const newApplications = await countNewApplications();

  return (
    <>
      <nav className="top">
        <span className="brand">MonAvi Admin</span>
        <Link href="/">Resumen</Link>
        <Link href="/merchants">Comercios y ofertas</Link>
        <Link href="/applications">
          Solicitudes
          {newApplications > 0 && <span className="nav-badge">{newApplications}</span>}
        </Link>
        <Link href="/redemptions">Canjes</Link>
        <Link href="/insights">Estudio de mercado</Link>
        <Link href="/card-reports">Reportes de tarjeta</Link>
        <Link href="/bank-partners">Bancos patrocinadores</Link>
        <Link href="/bank-reports">Reportes de banco</Link>
        <Link href="/dgi-verification">Facturas DGI</Link>
        <Link href="/alerts">Alertas</Link>
        <form action={logout}>
          <button type="submit" className="secondary">
            Salir
          </button>
        </form>
      </nav>
      <div className="page">{children}</div>
    </>
  );
}

import Link from "next/link";
import { logout } from "../login/actions";
import { supabaseAdmin } from "@/lib/supabase-admin";

// Panel interno: siempre datos frescos de la base. Sin esto, Next
// prerenderiza en el build las paginas sin searchParams (p. ej.
// /merchants, /alerts) y mostraria datos del momento del deploy.
export const dynamic = "force-dynamic";

/// Cuenta las solicitudes nuevas y, de paso, comprueba que el panel
/// pueda hablar con Supabase. Si la llave esta mal (p. ej. una
/// SUPABASE_SERVICE_ROLE_KEY cambiada por error en Vercel), todas las
/// paginas se verian vacias sin explicar por que: se muestra el error.
async function checkSupabase(): Promise<{ newApplications: number; error: string | null }> {
  try {
    const { count, error } = await supabaseAdmin()
      .from("merchant_applications")
      .select("id", { count: "exact", head: true })
      .eq("status", "nueva");
    if (error) return { newApplications: 0, error: error.message || "error desconocido" };
    return { newApplications: count ?? 0, error: null };
  } catch (error) {
    return { newApplications: 0, error: error instanceof Error ? error.message : String(error) };
  }
}

export default async function ProtectedLayout({ children }: { children: React.ReactNode }) {
  const { newApplications, error: supabaseError } = await checkSupabase();

  return (
    <>
      <nav className="top">
        <span className="brand">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className="brand-mark" src="/monavi-mark.svg" alt="" aria-hidden="true" />
          MonAvi Admin
        </span>
        <Link href="/">Resumen</Link>
        <Link href="/merchants">Comercios y productos</Link>
        <Link href="/applications">
          Solicitudes
          {newApplications > 0 && <span className="nav-badge">{newApplications}</span>}
        </Link>
        <Link href="/redemptions">Canjes</Link>
        <Link href="/clientes">Clientes</Link>
        <Link href="/notificaciones">Notificaciones</Link>
        <Link href="/bonos">Bonos y regalos</Link>
        <Link href="/campaigns">Campañas de marcas</Link>
        <Link href="/insights">Estudio de mercado</Link>
        <Link href="/dgi-verification">Facturas DGI</Link>
        <Link href="/alerts">Alertas</Link>
        <form action={logout}>
          <button type="submit" className="secondary">
            Salir
          </button>
        </form>
      </nav>
      <div className="page">{supabaseError && (
          <div className="card" style={{ borderColor: "#B5453A", marginBottom: 16 }}>
            <strong>El panel no se puede conectar con Supabase:</strong> {supabaseError}.
            <br />
            Revisa en Vercel la variable <code>SUPABASE_SERVICE_ROLE_KEY</code> (Supabase &gt; Project Settings &gt;
            API Keys) y <code>SUPABASE_URL</code>, y vuelve a publicar (Deployments &gt; Redeploy).
          </div>
        )}
        {children}</div>
    </>
  );
}

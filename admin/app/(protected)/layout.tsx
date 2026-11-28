import { Inter } from "next/font/google";
import Sidebar, { type NavGroup } from "@/components/Sidebar";
import { logout } from "../login/actions";
import { supabaseAdmin } from "@/lib/supabase-admin";

// Panel interno: siempre datos frescos de la base. Sin esto, Next
// prerenderiza en el build las paginas sin searchParams (p. ej.
// /merchants, /alerts) y mostraria datos del momento del deploy.
export const dynamic = "force-dynamic";

// La fuente se sirve desde el propio panel (next/font): cumple la CSP.
const inter = Inter({ subsets: ["latin"], display: "swap", variable: "--font-inter" });

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

  const groups: NavGroup[] = [
    { title: "General", items: [{ href: "/", label: "Resumen", icon: "home" }] },
    {
      title: "Comercios",
      items: [
        { href: "/merchants", label: "Comercios y productos", icon: "store" },
        { href: "/categorias", label: "Categorías", icon: "tag" },
        { href: "/applications", label: "Solicitudes", icon: "inbox", badge: newApplications },
        { href: "/redemptions", label: "Canjes", icon: "check" },
        { href: "/cercania", label: "Avisos por cercanía", icon: "pin" },
      ],
    },
    {
      title: "Clientes",
      items: [
        { href: "/clientes", label: "Clientes", icon: "users" },
        { href: "/cupones", label: "Cupones", icon: "gift" },
        { href: "/referidos", label: "Invita amigos", icon: "userPlus" },
        { href: "/notificaciones", label: "Notificaciones", icon: "bell" },
      ],
    },
    {
      title: "Datos y marcas",
      items: [
        { href: "/campaigns", label: "Campañas de marcas", icon: "megaphone" },
        { href: "/insights", label: "Estudio de mercado", icon: "chart" },
        { href: "/dgi-verification", label: "Facturas DGI", icon: "receipt" },
        { href: "/revision-cashback", label: "Revisión de cashback", icon: "shield" },
        { href: "/verificacion-ingresos", label: "Verificación de ingresos", icon: "wallet" },
      ],
    },
    {
      title: "Asesoría",
      items: [{ href: "/ensenanzas", label: "Enseñanzas", icon: "star" }],
    },
    {
      title: "Sistema",
      items: [
        { href: "/paises", label: "Países", icon: "globe" },
        { href: "/ia", label: "Costo de IA", icon: "cpu" },
        { href: "/alerts", label: "Alertas", icon: "alert" },
        { href: "/seguridad", label: "Seguridad", icon: "shield" },
      ],
    },
  ];

  return (
    <div className={`shell ${inter.variable}`}>
      <Sidebar groups={groups} logoutAction={logout} />
      <main className="main">
        <div className="page">
          {supabaseError && (
            <div className="card" style={{ borderColor: "#B5453A", marginBottom: 16 }}>
              <strong>El panel no se puede conectar con Supabase:</strong> {supabaseError}.
              <br />
              Revisa en Vercel la variable <code>SUPABASE_SERVICE_ROLE_KEY</code> (Supabase &gt; Project Settings &gt;
              API Keys) y <code>SUPABASE_URL</code>, y vuelve a publicar (Deployments &gt; Redeploy).
            </div>
          )}
          {children}
        </div>
      </main>
    </div>
  );
}

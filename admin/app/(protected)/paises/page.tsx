import { supabaseAdmin } from "@/lib/supabase-admin";
import { setColombiaEnabled } from "./actions";

export const dynamic = "force-dynamic";

export default async function PaisesPage() {
  const supabase = supabaseAdmin();
  const [{ data: flag }, { count: colombianos }] = await Promise.all([
    supabase.from("app_config").select("value").eq("key", "colombia_enabled").maybeSingle<{ value: unknown }>(),
    supabase.from("profiles").select("id", { count: "exact", head: true }).eq("country", "CO"),
  ]);
  const enabled = flag?.value === true;

  return (
    <>
      <h1>Países</h1>
      <p className="text-dim">
        Desde la versión 1.0.7 la app puede funcionar en Panamá (USD) y en Colombia (pesos colombianos). Mientras
        Colombia esté apagada, la app no muestra “¿Dónde vives?” ni “País y moneda”: todo el mundo usa Panamá, igual
        que antes.
      </p>

      <div className="card">
        <h3>🇵🇦 Panamá</h3>
        <p>
          <span className="badge active">activo</span> Siempre disponible. Moneda: USD.
        </p>
      </div>

      <div className="card">
        <h3>🇨🇴 Colombia</h3>
        <p>
          Estado: <span className={`badge ${enabled ? "active" : "paused"}`}>{enabled ? "activo" : "apagado"}</span>
        </p>
        <p className="text-dim" style={{ marginBottom: 10 }}>
          {enabled
            ? "La app ofrece Colombia al registrarse y en Ajustes > Mi perfil. Si lo apagas, nadie nuevo puede elegirlo; quien ya está en Colombia lo conserva y puede volver a Panamá."
            : "Al activarlo, la app ofrece Colombia (pesos, voz con “luca” y “palo”, Nequi/Daviplata) la próxima vez que se abra. Antes, confirma las políticas para Colombia y la disponibilidad en la App Store."}
        </p>
        <p className="text-dim" style={{ marginBottom: 10 }}>Cuentas en Colombia hoy: {colombianos ?? 0}</p>
        <form action={setColombiaEnabled.bind(null, !enabled)}>
          <button type="submit" className={enabled ? "danger" : undefined}>
            {enabled ? "Apagar Colombia" : "Activar Colombia"}
          </button>
        </form>
      </div>
    </>
  );
}

import { supabaseAdmin } from "@/lib/supabase-admin";
import StatTile from "@/components/StatTile";
import TimeChart, { type Point } from "@/components/charts/TimeChart";
import BarList from "@/components/BarList";

type Item = { label: string; v: number };
type Stats = {
  total: number;
  new_30: number;
  new_prev_30: number;
  active_30: number;
  active_prev_30: number;
  older_total: number;
  older_retained: number;
  push: number;
  pro: number;
  consent_estudio: number;
  consent_ofertas: number;
  with_receipt: number;
  segments: { active: number; dormant: number; never: number };
  series_total: Point[];
  series_signups_weekly: Point[];
  genders: Item[];
  ages: Item[];
};

const pctOf = (part: number, whole: number) => (whole > 0 ? Math.round((part / whole) * 100) : 0);
const tail = (series: Point[] | undefined, n = 14) => (series ?? []).slice(-n).map((p) => p.v);

/// Estadisticas de clientes: crecimiento, actividad, retencion y quienes son.
export default async function CustomerStats() {
  const { data, error } = await supabaseAdmin().rpc("admin_customers_stats");
  if (error) return <div className="card error">No se pudieron calcular las estadísticas de clientes: {error.message}</div>;
  const s = (data ?? {}) as Stats;
  const total = s.total ?? 0;
  const segments = s.segments ?? { active: 0, dormant: 0, never: 0 };
  const retention = pctOf(s.older_retained ?? 0, s.older_total ?? 0);

  return (
    <>
      <section className="tiles">
        <StatTile label="Clientes" value={total} icon="users" hint={`+${s.new_30 ?? 0} en 30 días`} trend={tail(s.series_total)} />
        <StatTile label="Nuevos (30 días)" value={s.new_30 ?? 0} icon="userPlus" previous={s.new_prev_30} trend={tail(s.series_signups_weekly, 12)} />
        <StatTile label="Activos (30 días)" value={s.active_30 ?? 0} icon="activity" previous={s.active_prev_30} />
        <StatTile
          label="Siguen usando la app"
          value={retention}
          format="pct"
          icon="check"
          hint={(s.older_total ?? 0) > 0 ? `${s.older_retained} de ${s.older_total} con más de 30 días` : "Aún nadie lleva más de 30 días"}
        />
        <StatTile label="Escanearon una factura" value={s.with_receipt ?? 0} icon="receipt" hint={`${pctOf(s.with_receipt ?? 0, total)}% de los clientes`} />
        <StatTile label="Avisos activados" value={s.push ?? 0} icon="bell" hint={`${pctOf(s.push ?? 0, total)}% pueden recibir notificaciones`} />
        <StatTile label="Suscriptores Pro" value={s.pro ?? 0} icon="star" hint={`${pctOf(s.pro ?? 0, total)}% de los clientes`} />
        <StatTile label="Aceptaron estudio de mercado" value={s.consent_estudio ?? 0} icon="chart" hint={`${s.consent_ofertas ?? 0} aceptaron recibir ofertas`} />
      </section>

      <section className="chart-grid">
        <div className="card chart-card">
          <div className="chart-head">
            <h3>Crecimiento de clientes</h3>
            <span>Total acumulado, últimos 90 días</span>
          </div>
          <TimeChart data={s.series_total ?? []} kind="area" unit={["cliente", "clientes"]} />
        </div>
        <div className="card chart-card">
          <div className="chart-head">
            <h3>Registros por semana</h3>
            <span>Últimas 12 semanas</span>
          </div>
          <TimeChart data={s.series_signups_weekly ?? []} kind="bar" period="semana" unit={["registro", "registros"]} />
        </div>
      </section>

      <section className="dash-split">
        <div className="card">
          <h3>Cómo están los clientes</h3>
          <p className="text-dim">Cuántos usan la app, cuántos la dejaron y cuántos nunca empezaron.</p>
          <BarList
            total={total}
            items={[
              { label: "Activos: anotaron algo en los últimos 30 días", v: segments.active },
              { label: "La dejaron: sin movimientos en 30 días", v: segments.dormant },
              { label: "Se registraron pero nunca anotaron nada", v: segments.never },
            ]}
          />
        </div>
        <div className="card">
          <h3>Quiénes son</h3>
          <p className="text-dim">Según lo que llenaron en su perfil.</p>
          <div className="demo-split">
            <div>
              <h4>Género</h4>
              <BarList items={s.genders ?? []} total={total} />
            </div>
            <div>
              <h4>Edad</h4>
              <BarList items={s.ages ?? []} total={total} />
            </div>
          </div>
        </div>
      </section>
    </>
  );
}

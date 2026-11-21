import Link from "next/link";
import { supabaseAdmin } from "@/lib/supabase-admin";
import StatTile from "@/components/StatTile";
import TimeChart, { type Point } from "@/components/charts/TimeChart";
import BarList from "@/components/BarList";
import Icon from "@/components/icons";

type Item = { label: string; v: number };
type Stats = {
  uses_30: number;
  uses_prev_30: number;
  canjes_30: number;
  descuentos_30: number;
  cupones_30: number;
  clients_30: number;
  cashback_spent_30: number;
  via_caja_30: number;
  via_panel_30: number;
  pending: number;
  overdue: number;
  lost_30: number;
  created_30: number;
  coupons_issued: number;
  coupons_used: number;
  series_daily: Point[];
  top_merchants: Item[];
  top_items: Item[];
};

const pctOf = (part: number, whole: number) => (whole > 0 ? Math.round((part / whole) * 100) : 0);

/// Estadisticas de canjes, descuentos y cupones usados en caja.
export default async function RedemptionStats() {
  const { data, error } = await supabaseAdmin().rpc("admin_redemptions_stats");
  if (error) return <div className="card error">No se pudieron calcular las estadísticas de canjes: {error.message}</div>;
  const s = (data ?? {}) as Stats;
  const uses = s.uses_30 ?? 0;

  return (
    <>
      {(s.overdue ?? 0) > 0 && (
        <div className="attention">
          <span className="attention-item">
            <Icon name="alert" size={16} />
            {s.overdue} código(s) vencido(s) sin liberar: esta noche se liberan y se devuelve el valor al cliente
          </span>
        </div>
      )}

      <section className="tiles">
        <StatTile label="Usados en caja (30 días)" value={uses} icon="ticket" previous={s.uses_prev_30}
          trend={(s.series_daily ?? []).slice(-14).map((p) => p.v)} />
        <StatTile label="Clientes que canjearon" value={s.clients_30 ?? 0} icon="users" hint="En los últimos 30 días" />
        <StatTile label="Cashback usado en canjes" value={s.cashback_spent_30 ?? 0} format="money" icon="wallet" hint="En los últimos 30 días" />
        <StatTile label="Códigos por entregar" value={s.pending ?? 0} icon="inbox"
          hint={(s.overdue ?? 0) > 0 ? `${s.overdue} vencidos por liberar` : "Vigentes, esperando ir a caja"} />
      </section>

      <section className="chart-grid">
        <div className="card chart-card">
          <div className="chart-head">
            <h3>Usados en caja por día</h3>
            <span>Canjes, descuentos y cupones · 30 días</span>
          </div>
          <TimeChart data={s.series_daily ?? []} kind="bar" unit={["uso", "usos"]} />
        </div>
        <div className="card chart-card">
          <div className="chart-head">
            <h3>Qué se usa</h3>
            <span>Últimos 30 días</span>
          </div>
          <BarList
            total={uses}
            empty="Todavía no hay usos en caja este mes."
            items={[
              { label: "Descuentos por ser de MonAvi", v: s.descuentos_30 ?? 0 },
              { label: "Premios con cashback", v: s.canjes_30 ?? 0 },
              { label: "Cupones regalados", v: s.cupones_30 ?? 0 },
            ]}
          />
          <div className="mini-stats">
            <div>
              <span>Validados en caja</span>
              <strong>{pctOf(s.via_caja_30 ?? 0, uses)}%</strong>
            </div>
            <div>
              <span>Cupones usados</span>
              <strong>
                {(s.coupons_used ?? 0).toLocaleString("es-PA")} / {(s.coupons_issued ?? 0).toLocaleString("es-PA")}
              </strong>
            </div>
            <div>
              <span>Vencidos o cancelados</span>
              <strong>{pctOf(s.lost_30 ?? 0, s.created_30 ?? 0)}%</strong>
            </div>
          </div>
        </div>
      </section>

      <section className="dash-split">
        <div className="card">
          <h3>Comercios con más usos</h3>
          <p className="text-dim">Últimos 30 días. Toca <Link href="/merchants">Comercios</Link> para ver cada ficha.</p>
          <BarList items={s.top_merchants ?? []} empty="Cuando los clientes usen sus códigos en caja, aparecen aquí." />
        </div>
        <div className="card">
          <h3>Productos y descuentos más usados</h3>
          <p className="text-dim">Últimos 30 días.</p>
          <BarList items={s.top_items ?? []} empty="Todavía no hay usos este mes." />
        </div>
      </section>
    </>
  );
}

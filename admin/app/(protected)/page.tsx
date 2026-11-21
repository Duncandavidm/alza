import Link from "next/link";
import { headers } from "next/headers";
import { supabaseAdmin } from "@/lib/supabase-admin";
import CopyButton from "@/components/CopyButton";
import StatTile from "@/components/StatTile";
import TimeChart, { type Point } from "@/components/charts/TimeChart";
import Icon from "@/components/icons";
import { fetchProBreakdown } from "@/lib/pro";

type Stats = {
  users_total: number;
  users_new_7: number;
  users_new_prev_7: number;
  users_new_30: number;
  users_new_prev_30: number;
  active_1: number;
  active_7: number;
  active_30: number;
  active_prev_30: number;
  pro_active: number;
  receipts_total: number;
  receipts_30: number;
  receipts_prev_30: number;
  receipts_pending: number;
  cashback_earned_30: number;
  cashback_earned_prev_30: number;
  cashback_spent_30: number;
  redemptions_30: number;
  benefits_30: number;
  coupons_used_30: number;
  coupons_issued_30: number;
  uses_prev_30: number;
  merchants_active: number;
  merchants_hidden: number;
  applications_new: number;
  referrals_30: number;
  ai_cost_30: number;
  push_devices: number;
  series_signups: Point[];
  series_active: Point[];
  series_receipts: Point[];
  series_uses_weekly: Point[];
  funnel: { registered: number; logged: number; scanned: number; redeemed: number };
  top_merchants: { name: string; uses: number }[];
};

async function countRows(table: string, filters: Record<string, string>): Promise<number> {
  let query = supabaseAdmin().from(table).select("id", { count: "exact", head: true });
  for (const [column, value] of Object.entries(filters)) query = query.eq(column, value);
  const { count } = await query;
  return count ?? 0;
}

const last = (series: Point[] | undefined, n = 14) => (series ?? []).slice(-n).map((p) => p.v);

function greeting() {
  const hour = Number(new Date().toLocaleString("en-US", { hour: "numeric", hour12: false, timeZone: "America/Panama" }));
  return hour < 12 ? "Buenos días" : hour < 19 ? "Buenas tardes" : "Buenas noches";
}

/// Dashboard: como va la app de un vistazo (crecimiento, uso, facturas,
/// cashback, canjes) con lo que necesita atencion arriba.
export default async function DashboardPage() {
  const [{ data, error }, budgetExhausted, pro] = await Promise.all([
    supabaseAdmin().rpc("admin_dashboard_stats"),
    countRows("partner_merchant_offers", { status: "budget_exhausted" }),
    fetchProBreakdown(),
  ]);
  const s = (data ?? {}) as Stats;
  const uses30 = (s.redemptions_30 ?? 0) + (s.benefits_30 ?? 0) + (s.coupons_used_30 ?? 0);
  const funnel = s.funnel ?? { registered: 0, logged: 0, scanned: 0, redeemed: 0 };

  const headerList = await headers();
  const host = headerList.get("x-forwarded-host") ?? headerList.get("host") ?? "monavi.maday.app";
  const protocol = headerList.get("x-forwarded-proto") ?? (host.startsWith("localhost") ? "http" : "https");
  const landingUrl = `${protocol}://${host}/aliados`;
  const today = new Date().toLocaleDateString("es-PA", { weekday: "long", day: "numeric", month: "long", timeZone: "America/Panama" });

  const attention = [
    s.applications_new > 0 && { href: "/applications?status=nueva", text: `${s.applications_new} solicitud(es) de comercios nuevas`, icon: "inbox" },
    s.receipts_pending > 0 && { href: "/dgi-verification", text: `${s.receipts_pending} factura(s) esperando verificación DGI`, icon: "receipt" },
    budgetExhausted > 0 && { href: "/alerts", text: `${budgetExhausted} oferta(s) con presupuesto agotado`, icon: "alert" },
    s.merchants_hidden > 0 && { href: "/merchants", text: `${s.merchants_hidden} comercio(s) sin publicar`, icon: "store" },
  ].filter(Boolean) as { href: string; text: string; icon: string }[];

  const funnelSteps = [
    { label: "Se registraron", value: funnel.registered },
    { label: "Anotaron al menos un movimiento", value: funnel.logged },
    { label: "Escanearon una factura fiscal", value: funnel.scanned },
    { label: "Usaron un canje, descuento o cupón", value: funnel.redeemed },
  ];

  return (
    <div className="dash">
      <header className="dash-head">
        <div>
          <p className="dash-date">{today}</p>
          <h1>{greeting()} 👋</h1>
          <p className="text-dim">Así va MonAvi. Números de los últimos 30 días; el % compara con los 30 días anteriores.</p>
        </div>
        <div className="dash-actions">
          <Link href="/merchants" className="button secondary-link">
            <Icon name="plus" size={16} /> Nuevo comercio
          </Link>
          <Link href="/cupones/regalar" className="button secondary-link">
            <Icon name="gift" size={16} /> Regalar cupones
          </Link>
          <Link href="/notificaciones" className="button">
            <Icon name="bell" size={16} /> Enviar aviso
          </Link>
        </div>
      </header>

      {error && <div className="card error">No se pudieron calcular las estadísticas: {error.message}</div>}

      {attention.length > 0 && (
        <div className="attention">
          {attention.map((item) => (
            <Link key={item.href} href={item.href} className="attention-item">
              <Icon name={item.icon} size={16} />
              {item.text}
              <span aria-hidden="true">→</span>
            </Link>
          ))}
        </div>
      )}

      <section className="tiles">
        <StatTile label="Usuarios" value={s.users_total ?? 0} icon="users" hint={`+${s.users_new_30 ?? 0} este mes`} trend={last(s.series_signups)} href="/clientes" />
        <StatTile label="Nuevos (30 días)" value={s.users_new_30 ?? 0} icon="userPlus" previous={s.users_new_prev_30}
          trend={last(s.series_signups)} />
        <StatTile label="Activos (30 días)" value={s.active_30 ?? 0} icon="activity" previous={s.active_prev_30}
          trend={last(s.series_active)} hint={`${s.active_7 ?? 0} esta semana · ${s.active_1 ?? 0} hoy`} />
        <StatTile label="Facturas escaneadas" value={s.receipts_30 ?? 0} icon="receipt" previous={s.receipts_prev_30}
          trend={last(s.series_receipts)} href="/dgi-verification" />
        <StatTile label="Cashback ganado" value={s.cashback_earned_30 ?? 0} format="money" icon="wallet" previous={s.cashback_earned_prev_30}
          />
        <StatTile label="Canjes, descuentos y cupones" value={uses30} icon="ticket" previous={s.uses_prev_30}
          trend={last(s.series_uses_weekly, 12)} href="/redemptions" />
        <StatTile label="Comercios publicados" value={s.merchants_active ?? 0} icon="store" hint={`${s.applications_new ?? 0} solicitudes nuevas`}
          href="/merchants" />
        <StatTile label="Pagan Pro" value={pro.paying} icon="star"
          hint={`~$${Math.round(pro.netMonthly).toLocaleString("es-PA")}/mes · ${pro.lifetime} de por vida`} href="/clientes" />
      </section>

      <section className="chart-grid">
        <div className="card chart-card">
          <div className="chart-head">
            <h3>Nuevos usuarios por día</h3>
            <span>{(s.users_new_30 ?? 0).toLocaleString("es-PA")} en 30 días</span>
          </div>
          <TimeChart data={s.series_signups ?? []} kind="area" unit={["usuario nuevo", "usuarios nuevos"]} />
        </div>
        <div className="card chart-card">
          <div className="chart-head">
            <h3>Usuarios activos por día</h3>
            <span>Anotaron al menos un movimiento</span>
          </div>
          <TimeChart data={s.series_active ?? []} kind="area" unit={["usuario activo", "usuarios activos"]} />
        </div>
        <div className="card chart-card">
          <div className="chart-head">
            <h3>Facturas fiscales escaneadas</h3>
            <span>{(s.receipts_total ?? 0).toLocaleString("es-PA")} confirmadas en total</span>
          </div>
          <TimeChart data={s.series_receipts ?? []} kind="bar" unit={["factura", "facturas"]} />
        </div>
        <div className="card chart-card">
          <div className="chart-head">
            <h3>Canjes, descuentos y cupones por semana</h3>
            <span>Usados en caja</span>
          </div>
          <TimeChart data={s.series_uses_weekly ?? []} kind="bar" period="semana" unit={["uso", "usos"]} />
        </div>
      </section>

      <section className="dash-split">
        <div className="card">
          <h3>Embudo de la app</h3>
          <p className="text-dim">De todos los que se registraron, cuántos llegan a cada paso.</p>
          <div className="funnel">
            {funnelSteps.map((step, i) => {
              const pct = funnel.registered > 0 ? Math.round((step.value / funnel.registered) * 100) : 0;
              return (
                <div key={step.label} className="funnel-row" style={{ ["--i" as string]: i } as React.CSSProperties}>
                  <div className="funnel-label">
                    <span>{step.label}</span>
                    <strong>
                      {step.value.toLocaleString("es-PA")} <em>{pct}%</em>
                    </strong>
                  </div>
                  <div className="funnel-track">
                    <div className="funnel-fill" style={{ width: `${Math.max(pct, step.value > 0 ? 2 : 0)}%` }} />
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        <div className="card">
          <h3>Más usados (30 días)</h3>
          <p className="text-dim">Comercios con más canjes, descuentos y cupones usados.</p>
          {(s.top_merchants ?? []).length === 0 ? (
            <div className="empty">
              <Icon name="store" size={28} />
              <p>Todavía no hay canjes este mes. Cuando los clientes usen sus códigos en caja, aparecen aquí.</p>
            </div>
          ) : (
            <ol className="ranking">
              {s.top_merchants.map((m, i) => (
                <li key={m.name}>
                  <span className="rank">{i + 1}</span>
                  <span className="rank-name">{m.name}</span>
                  <strong>{m.uses.toLocaleString("es-PA")}</strong>
                </li>
              ))}
            </ol>
          )}
          <div className="mini-stats">
            <div>
              <span>Cupones entregados</span>
              <strong>{(s.coupons_issued_30 ?? 0).toLocaleString("es-PA")}</strong>
            </div>
            <div>
              <span>Amigos invitados</span>
              <strong>{(s.referrals_30 ?? 0).toLocaleString("es-PA")}</strong>
            </div>
            <div>
              <span>Costo de IA</span>
              <strong>${Number(s.ai_cost_30 ?? 0).toFixed(2)}</strong>
            </div>
          </div>
        </div>
      </section>

      <section className="dash-split">
        <div className="card">
          <h3>Landing para comercios aliados</h3>
          <p className="text-dim">
            Página pública donde los negocios piden ser aliados. Las solicitudes llegan a <Link href="/applications">Solicitudes</Link>.
          </p>
          <div className="inline-actions">
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
            Reporte agregado y anónimo de qué se compra, dónde y a qué precio, para ofrecer a marcas y aliados.
          </p>
          <Link href="/insights" className="button secondary-link">
            <Icon name="chart" size={16} /> Abrir estudio de mercado
          </Link>
        </div>
      </section>
    </div>
  );
}

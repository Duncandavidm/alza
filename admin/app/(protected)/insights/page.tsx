import Link from "next/link";
import { supabaseAdmin } from "@/lib/supabase-admin";
import {
  ALLOWED_DAYS,
  GENDER_LABELS,
  WEEKDAY_LABELS,
  fetchMarketInsights,
  parseDays,
  parseRuc,
  paymentMethodLabel,
  weekdayLabel,
} from "@/lib/insights";
import { formatDateTime, formatDecimal, formatInt, formatMoney, formatPercent, num } from "@/lib/format";
import PrintButton from "@/components/PrintButton";

export const dynamic = "force-dynamic";

type BarItem = { label: string; value: number; detail?: string; tag?: string };

export default async function InsightsPage({ searchParams }: { searchParams: Promise<{ days?: string; ruc?: string }> }) {
  const params = await searchParams;
  const days = parseDays(params.days);
  const ruc = parseRuc(params.ruc);

  const [{ data: merchants }, result] = await Promise.all([
    supabaseAdmin()
      .from("partner_merchants")
      .select("id, name, ruc")
      .order("name")
      .returns<{ id: string; name: string; ruc: string }[]>(),
    fetchMarketInsights(days, ruc),
  ]);

  const partner = ruc ? (merchants ?? []).find((merchant) => merchant.ruc === ruc) : undefined;
  const scopeLabel = ruc ? `Clientes de ${partner?.name ?? `RUC ${ruc}`}` : "Panorama general de MonAvi";
  const exportBase = `/insights/export?days=${days}${ruc ? `&ruc=${encodeURIComponent(ruc)}` : ""}`;

  const data = result.data;
  const isEmpty = !data || (num(data.summary.receipts) === 0 && num(data.summary.people) === 0);

  return (
    <div className="insights">
      <div className="insights-head">
        <div>
          <h1>Estudio de mercado</h1>
          <p className="text-dim" style={{ margin: 0 }}>
            {scopeLabel} · últimos {days} días
            {data?.generated_at ? ` · generado ${formatDateTime(data.generated_at)}` : ""}
          </p>
        </div>
        <div className="no-print">
          <PrintButton />
        </div>
      </div>

      <form method="get" className="card grid-form no-print">
        <div className="field">
          <label>Periodo</label>
          <select name="days" defaultValue={String(days)}>
            {ALLOWED_DAYS.map((value) => (
              <option key={value} value={value}>
                Últimos {value} días
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label>Reporte para un aliado</label>
          <select name="ruc" defaultValue={ruc ?? ""}>
            <option value="">Todos (panorama general)</option>
            {ruc && !partner && <option value={ruc}>RUC {ruc}</option>}
            {(merchants ?? []).map((merchant) => (
              <option key={merchant.id} value={merchant.ruc}>
                {merchant.name} — {merchant.ruc}
              </option>
            ))}
          </select>
        </div>
        <div className="field" style={{ alignSelf: "end", display: "flex", gap: 8 }}>
          <button type="submit">Ver reporte</button>
          {ruc && (
            <Link href={`/insights?days=${days}`} className="button secondary-link">
              Quitar aliado
            </Link>
          )}
        </div>
      </form>

      {ruc && (
        <p className="text-dim">
          Con un aliado seleccionado, el estudio solo considera a las personas que compraron en ese comercio (por RUC de sus
          facturas DGI): es lo que se le puede compartir sobre su propia clientela.
        </p>
      )}

      {result.error && (
        <div className="card">
          <p className="error">No se pudo generar el estudio: {result.error}</p>
        </div>
      )}

      {data && isEmpty && (
        <div className="card empty-state">
          <h3>Todavía no hay datos para este periodo</h3>
          <p className="text-dim">
            El estudio se arma con las facturas DGI confirmadas y los gastos que registran los usuarios. Cuando haya al menos
            5 personas con actividad{ruc ? " en este comercio" : ""}, aquí aparecerán los resultados. Prueba con un periodo más
            largo.
          </p>
        </div>
      )}

      {data && !isEmpty && (
        <>
          <Section
            title="Resumen"
            caption="El tamaño de la audiencia y cuánto compra. El ticket mediano es más representativo que el promedio cuando hay compras muy grandes."
            csv={`${exportBase}&section=summary`}
          >
            <div className="kpi-grid">
              <Kpi label="Personas" value={formatInt(data.summary.people)} />
              <Kpi label="Facturas" value={formatInt(data.summary.receipts)} />
              <Kpi label="Total facturado" value={formatMoney(data.summary.receipts_total)} />
              <Kpi label="Ticket promedio" value={formatMoney(data.summary.avg_ticket)} />
              <Kpi label="Ticket mediano" value={formatMoney(data.summary.median_ticket)} />
              <Kpi label="Gasto promedio por persona al mes" value={formatMoney(data.summary.avg_spend_per_person_month)} />
              <Kpi label="Compras por persona al mes" value={formatDecimal(data.summary.receipts_per_person_month, 1)} />
              <Kpi label="Puntos emitidos" value={formatInt(data.summary.points_issued)} />
              <Kpi label="Canjes" value={formatInt(data.summary.redemptions)} />
            </div>
          </Section>

          <div className="insights-two">
            <Section
              title="Formas de pago"
              caption="Cómo pagan. Útil para decidir promociones con bancos o tarjetas y para asegurar que aceptas los métodos que más usan."
              csv={`${exportBase}&section=payment_methods`}
            >
              <BarList
                items={data.payment_methods.map((row) => ({
                  label: paymentMethodLabel(row.method),
                  value: num(row.receipts),
                  detail: `${formatPercent(row.share)} · ${formatInt(row.receipts)} facturas`,
                }))}
              />
            </Section>

            <Section
              title="Ticket por rango"
              caption="Cuántas compras caen en cada rango de monto. Ayuda a fijar el valor de un combo o el costo en puntos de un producto canjeable."
              csv={`${exportBase}&section=ticket_ranges`}
            >
              <BarList
                items={data.ticket_ranges.map((row) => ({
                  label: row.range ?? "—",
                  value: num(row.receipts),
                  detail: `${formatInt(row.receipts)} facturas`,
                }))}
              />
            </Section>
          </div>

          <div className="insights-two">
            <Section
              title="Género"
              caption="Quiénes compran y cuánto gastan en promedio. Sirve para afinar el tono y el público de tus anuncios."
              csv={`${exportBase}&section=gender`}
            >
              <BarList
                items={data.gender.map((row) => ({
                  label: GENDER_LABELS[row.gender ?? "sin_dato"] ?? row.gender ?? "Sin dato",
                  value: num(row.people),
                  detail: `${formatInt(row.people)} personas · ticket ${formatMoney(row.avg_ticket)}`,
                }))}
              />
            </Section>

            <Section
              title="Edades"
              caption="Rango de edad de la audiencia y su ticket promedio. Indica en qué canales y con qué mensajes conviene comunicar."
              csv={`${exportBase}&section=age_ranges`}
            >
              <BarList
                items={data.age_ranges.map((row) => ({
                  label: row.age_range ?? "Sin dato",
                  value: num(row.people),
                  detail: `${formatInt(row.people)} personas · ticket ${formatMoney(row.avg_ticket)}`,
                }))}
              />
            </Section>
          </div>

          <Section
            title="Categorías de gasto"
            caption="En qué gasta esta audiencia (gastos registrados en la app). Muestra oportunidades de alianzas con rubros complementarios."
            csv={`${exportBase}&section=categories`}
          >
            <BarList
              items={data.categories.map((row) => ({
                label: row.category ?? "Sin categoría",
                value: num(row.total),
                detail: `${formatMoney(row.total)} · ${formatPercent(row.share)} · ${formatMoney(row.avg_per_person)} por persona`,
              }))}
            />
          </Section>

          <Section
            title="Compras por hora"
            caption="A qué hora compran (hora de Panamá). Programa anuncios, notificaciones y personal para las horas pico."
            csv={`${exportBase}&section=hours`}
          >
            <ColumnChart
              items={Array.from({ length: 24 }, (_, hour) => {
                const row = data.hours.find((item) => num(item.hour) === hour);
                return {
                  label: String(hour),
                  value: num(row?.receipts),
                  detail: `${hour}:00 — ${formatInt(row?.receipts)} facturas · ticket ${formatMoney(row?.avg_ticket ?? null)}`,
                };
              })}
            />
          </Section>

          <div className="insights-two">
            <Section
              title="Compras por día"
              caption="Qué días se compra más y con qué ticket. Los días flojos son buenos candidatos para promociones."
              csv={`${exportBase}&section=weekdays`}
            >
              <BarList
                items={WEEKDAY_LABELS.map((label, index) => {
                  const row = data.weekdays.find((item) => num(item.dow) === index + 1);
                  return {
                    label,
                    value: num(row?.receipts),
                    detail: `${formatInt(row?.receipts)} facturas · ticket ${formatMoney(row?.avg_ticket ?? null)}`,
                  };
                })}
              />
            </Section>

            <Section
              title="Clientes que vuelven"
              caption="Qué parte de los clientes compró más de una vez en el periodo. Es la mejor señal de lealtad."
              csv={`${exportBase}&section=loyalty`}
            >
              {data.loyalty && num(data.loyalty.customers) > 0 ? (
                <div className="kpi-grid">
                  <Kpi label="Clientes que vuelven" value={formatPercent(data.loyalty.returning_share)} />
                  <Kpi label="Clientes" value={formatInt(data.loyalty.customers)} />
                  <Kpi label="Volvieron (2+ compras)" value={formatInt(data.loyalty.returning)} />
                  <Kpi label="Visitas promedio" value={formatDecimal(data.loyalty.avg_visits, 1)} />
                </div>
              ) : (
                <p className="text-dim">Sin datos suficientes.</p>
              )}
            </Section>
          </div>

          <Section
            title="Mapa de calor: día × hora"
            caption="Cuándo se concentran las compras durante la semana. Entre más intenso el color, más facturas en ese día y hora."
            csv={`${exportBase}&section=heatmap`}
          >
            <Heatmap cells={data.heatmap.map((cell) => ({ dow: num(cell.dow), hour: num(cell.hour), receipts: num(cell.receipts) }))} />
          </Section>

          <Section
            title="Productos más comprados"
            caption="Los productos que más se repiten en las facturas. Úsalos para elegir qué ofrecer como canjeable o en combo."
            csv={`${exportBase}&section=top_products`}
          >
            <BarList
              items={data.top_products.map((row) => ({
                label: row.product ?? "—",
                value: num(row.times),
                detail: `${formatInt(row.times)} veces · ${formatInt(row.people)} personas · ${formatMoney(row.avg_price)} c/u`,
              }))}
            />
          </Section>

          <Section
            title="Comercios más visitados"
            caption={
              ruc
                ? "Otros comercios donde compran tus clientes. Muestra con quién compites y con quién podrías aliarte."
                : "Dónde compra la audiencia de MonAvi. Los que aún no son aliados son prospectos naturales para el programa."
            }
            csv={`${exportBase}&section=top_merchants`}
          >
            <BarList
              items={data.top_merchants.map((row) => ({
                label: row.merchant ?? `RUC ${row.ruc ?? "—"}`,
                value: num(row.visits),
                detail: `${formatInt(row.visits)} visitas · ${formatInt(row.people)} personas · ticket ${formatMoney(row.avg_ticket)}`,
                tag: row.is_partner ? "Aliado" : undefined,
              }))}
            />
          </Section>

          <Section
            title="Productos canjeados"
            caption="Qué recompensas eligen las personas con sus puntos. Indica qué tipo de producto atrae más visitas."
            csv={`${exportBase}&section=top_rewards`}
          >
            <BarList
              items={data.top_rewards.map((row) => ({
                label: `${row.reward ?? "—"}${row.merchant ? ` · ${row.merchant}` : ""}`,
                value: num(row.redemptions),
                detail: `${formatInt(row.redemptions)} canjes · ${formatInt(row.delivered)} entregados`,
              }))}
            />
          </Section>

          <Section
            title="Tendencia mensual"
            caption="Cómo evoluciona la actividad mes a mes. Sirve para medir el efecto de una campaña o de la temporada."
            csv={`${exportBase}&section=monthly`}
          >
            {data.monthly.length > 0 ? (
              <div className="table-scroll">
                <table>
                  <thead>
                    <tr>
                      <th>Mes</th>
                      <th>Facturas</th>
                      <th>Personas</th>
                      <th>Total</th>
                      <th>Ticket promedio</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.monthly.map((row) => (
                      <tr key={row.month ?? ""}>
                        <td>{monthLabel(row.month)}</td>
                        <td>{formatInt(row.receipts)}</td>
                        <td>{formatInt(row.people)}</td>
                        <td>{formatMoney(row.total)}</td>
                        <td>{formatMoney(row.avg_ticket)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : (
              <p className="text-dim">Sin datos suficientes.</p>
            )}
          </Section>
        </>
      )}

      <p className="insights-footer">
        Datos agregados y anónimos. Ningún grupo con menos de {formatInt(data?.min_users ?? 5)} personas se muestra.
      </p>
    </div>
  );
}

function monthLabel(month: string | null): string {
  if (!month) return "—";
  const [year, monthNumber] = month.split("-").map(Number);
  if (!year || !monthNumber) return month;
  const label = new Date(Date.UTC(year, monthNumber - 1, 15)).toLocaleDateString("es-PA", {
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });
  return label.charAt(0).toUpperCase() + label.slice(1);
}

function Section({
  title,
  caption,
  csv,
  children,
}: {
  title: string;
  caption: string;
  csv?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="card insights-section">
      <div className="insights-section-head">
        <h3>{title}</h3>
        {csv && (
          <a href={csv} className="no-print csv-link" download>
            Descargar CSV
          </a>
        )}
      </div>
      <p className="text-dim insights-caption">{caption}</p>
      {children}
    </section>
  );
}

function Kpi({ label, value }: { label: string; value: string }) {
  return (
    <div className="kpi">
      <div className="text-dim">{label}</div>
      <div className="kpi-value">{value}</div>
    </div>
  );
}

function BarList({ items }: { items: BarItem[] }) {
  if (items.length === 0) {
    return <p className="text-dim">Sin datos suficientes (ningún grupo llega a 5 personas).</p>;
  }
  const max = Math.max(...items.map((item) => item.value), 1);
  return (
    <ul className="bar-list">
      {items.map((item, index) => (
        <li key={`${item.label}-${index}`}>
          <div className="bar-list-label">
            <span>
              {item.label}
              {item.tag && <span className="badge active bar-tag">{item.tag}</span>}
            </span>
            <span className="text-dim">{item.detail}</span>
          </div>
          <div className="bar-track">
            <div className="bar-fill" style={{ width: `${Math.max((item.value / max) * 100, item.value > 0 ? 1.5 : 0)}%` }} />
          </div>
        </li>
      ))}
    </ul>
  );
}

function ColumnChart({ items }: { items: BarItem[] }) {
  const max = Math.max(...items.map((item) => item.value), 1);
  if (items.every((item) => item.value === 0)) {
    return <p className="text-dim">Sin datos suficientes.</p>;
  }
  return (
    <div className="column-chart" role="img" aria-label="Facturas por hora del día">
      {items.map((item) => (
        <div key={item.label} className="column" title={item.detail}>
          <div className="column-bar-area">
            <div className="column-bar" style={{ height: `${(item.value / max) * 100}%` }} />
          </div>
          <span className="column-label">{item.label}</span>
        </div>
      ))}
    </div>
  );
}

function Heatmap({ cells }: { cells: { dow: number; hour: number; receipts: number }[] }) {
  if (cells.length === 0) return <p className="text-dim">Sin datos suficientes.</p>;
  const lookup = new Map(cells.map((cell) => [`${cell.dow}-${cell.hour}`, cell.receipts]));
  const max = Math.max(...cells.map((cell) => cell.receipts), 1);
  const hours = Array.from({ length: 24 }, (_, hour) => hour);

  return (
    <div className="table-scroll">
      <div className="heatmap">
        <span />
        {hours.map((hour) => (
          <span key={`h-${hour}`} className="heatmap-hour">
            {hour}
          </span>
        ))}
        {WEEKDAY_LABELS.map((label, index) => (
          <HeatmapRow key={label} label={label} dow={index + 1} hours={hours} lookup={lookup} max={max} />
        ))}
      </div>
      <div className="heatmap-legend text-dim">
        Menos <span className="heatmap-cell" style={{ background: "rgba(0,165,133,0.08)" }} />
        <span className="heatmap-cell" style={{ background: "rgba(0,165,133,0.4)" }} />
        <span className="heatmap-cell" style={{ background: "rgba(0,165,133,1)" }} /> Más
      </div>
    </div>
  );
}

function HeatmapRow({
  label,
  dow,
  hours,
  lookup,
  max,
}: {
  label: string;
  dow: number;
  hours: number[];
  lookup: Map<string, number>;
  max: number;
}) {
  return (
    <>
      <span className="heatmap-day">{label.slice(0, 3)}</span>
      {hours.map((hour) => {
        const value = lookup.get(`${dow}-${hour}`) ?? 0;
        const intensity = value > 0 ? 0.12 + 0.88 * (value / max) : 0;
        return (
          <span
            key={hour}
            className="heatmap-cell"
            title={`${weekdayLabel(dow)} ${hour}:00 — ${formatInt(value)} facturas`}
            style={{ background: value > 0 ? `rgba(0,165,133,${intensity.toFixed(2)})` : undefined }}
          />
        );
      })}
    </>
  );
}

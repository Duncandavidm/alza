import Link from "next/link";
import { supabaseAdmin } from "@/lib/supabase-admin";
import {
  AGE_FILTERS,
  ALLOWED_DAYS,
  EXPENSE_CATEGORIES,
  GENDER_FILTERS,
  GENDER_LABELS,
  PAYMENT_FILTERS,
  PAYMENT_FILTER_LABELS,
  WEEKDAY_LABELS,
  fetchMarketInsights,
  filterChips,
  filtersQuery,
  hasFilters,
  parseDays,
  parseInsightFilters,
  parseRuc,
  paymentMethodLabel,
  weekdayLabel,
} from "@/lib/insights";
import { formatCashback, formatDateTime, formatDecimal, formatInt, formatMoney, formatPercent, num } from "@/lib/format";
import PrintButton from "@/components/PrintButton";
import { formatRewardValue, toRewardCurrency } from "@/lib/currency";
import { BarList, ColumnChart, Kpi } from "@/components/Charts";

export const dynamic = "force-dynamic";

type SearchParams = {
  days?: string;
  ruc?: string;
  gender?: string;
  age?: string;
  payment?: string;
  product?: string;
  category?: string;
};

export default async function InsightsPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const params = await searchParams;
  const days = parseDays(params.days);
  const ruc = parseRuc(params.ruc);
  const filters = parseInsightFilters((key) => params[key as keyof SearchParams]);
  const filtered = hasFilters(filters);
  const filterParams = filtersQuery(filters);

  const [{ data: merchants }, result] = await Promise.all([
    supabaseAdmin()
      .from("partner_merchants")
      .select("id, name, ruc")
      .order("name")
      .returns<{ id: string; name: string; ruc: string }[]>(),
    fetchMarketInsights(days, ruc, filters),
  ]);

  const partner = ruc ? (merchants ?? []).find((merchant) => merchant.ruc === ruc) : undefined;

  // Valor canjeado (entregado) en el periodo, separado por moneda: cada
  // canje guarda su currency (cashback en centavos, puntos tal cual).
  // Con filtros de segmento no aplica (los canjes no se segmentan).
  const redeemedTotals = { cashback: 0, puntos: 0 };
  if (!filtered && (!ruc || partner)) {
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
    let redeemedQuery = supabaseAdmin()
      .from("reward_redemptions")
      .select("points_cost, currency")
      .eq("status", "entregado")
      .gte("created_at", since)
      .limit(10000);
    if (partner) redeemedQuery = redeemedQuery.eq("merchant_id", partner.id);
    const { data: redeemedRows } = await redeemedQuery.returns<{ points_cost: number; currency: string | null }[]>();
    for (const row of redeemedRows ?? []) {
      redeemedTotals[toRewardCurrency(row.currency)] += num(row.points_cost);
    }
  }
  const scopeLabel = ruc ? `Clientes de ${partner?.name ?? `RUC ${ruc}`}` : "Panorama general de MonAvi";
  const baseQuery = `days=${days}${ruc ? `&ruc=${encodeURIComponent(ruc)}` : ""}`;
  const exportBase = `/insights/export?${baseQuery}${filterParams ? `&${filterParams}` : ""}`;
  const chips = filterChips(filters);

  const data = result.data;
  const tooSmall = Boolean(data?.too_small);
  const isEmpty = !data || (!tooSmall && num(data.summary.receipts) === 0 && num(data.summary.people) === 0);
  const minUsers = formatInt(data?.min_users ?? 5);

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
        <div className="no-print" style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
          <a href={`${exportBase}&format=json`} className="csv-link" download>
            Descargar todo (JSON)
          </a>
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
        <div className="field">
          <label>Género</label>
          <select name="gender" defaultValue={filters.gender ?? ""}>
            <option value="">Todos</option>
            {GENDER_FILTERS.map((value) => (
              <option key={value} value={value}>
                {GENDER_LABELS[value] ?? value}
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label>Edad</label>
          <select name="age" defaultValue={filters.age_range ?? ""}>
            <option value="">Todas</option>
            {AGE_FILTERS.map((value) => (
              <option key={value} value={value}>
                {value === "Sin dato" ? value : `${value} años`}
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label>Medio de pago</label>
          <select name="payment" defaultValue={filters.payment ?? ""}>
            <option value="">Todos</option>
            {PAYMENT_FILTERS.map((value) => (
              <option key={value} value={value}>
                {PAYMENT_FILTER_LABELS[value]}
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label>Producto (en la factura)</label>
          <input
            type="text"
            name="product"
            maxLength={80}
            defaultValue={filters.product ?? ""}
            placeholder="ej. coca cola"
          />
        </div>
        <div className="field">
          <label>Categoría de gasto</label>
          <select name="category" defaultValue={filters.category ?? ""}>
            <option value="">Todas</option>
            {filters.category && !(EXPENSE_CATEGORIES as readonly string[]).includes(filters.category) && (
              <option value={filters.category}>{filters.category}</option>
            )}
            {EXPENSE_CATEGORIES.map((value) => (
              <option key={value} value={value}>
                {value}
              </option>
            ))}
          </select>
        </div>
        <div className="field" style={{ alignSelf: "end", display: "flex", gap: 8 }}>
          <button type="submit">Ver reporte</button>
          {ruc && (
            <Link href={`/insights?days=${days}${filterParams ? `&${filterParams}` : ""}`} className="button secondary-link">
              Quitar aliado
            </Link>
          )}
        </div>
      </form>

      {chips.length > 0 && (
        <div className="filter-chips">
          <span className="text-dim">Segmento:</span>
          {chips.map((chip) => (
            <span key={chip.key} className="filter-chip">
              {chip.label}
            </span>
          ))}
          <Link href={`/insights?${baseQuery}`} className="no-print">
            Quitar filtros
          </Link>
        </div>
      )}

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

      {data && tooSmall && (
        <div className="card empty-state">
          <h3>Segmento demasiado pequeño</h3>
          <p>
            Este segmento tiene menos de {minUsers} personas: para proteger su privacidad no mostramos el detalle.
          </p>
          <div className="kpi-grid" style={{ maxWidth: 420, margin: "0 auto" }}>
            <Kpi label="Personas en el segmento" value={formatInt(data.summary.people)} />
            <Kpi label="Personas que aceptaron el estudio" value={formatInt(data.summary.consented_people)} />
          </div>
          <p className="text-dim">Prueba con menos filtros o un periodo más largo.</p>
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

      {data && !isEmpty && !tooSmall && (
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
              <Kpi label="Cashback emitido" value={formatCashback(data.summary.points_issued)} />
              <Kpi label="Canjes" value={formatInt(data.summary.redemptions)} />
              {!filtered && (
                <>
                  <Kpi label="Canjeado en cashback" value={formatRewardValue(redeemedTotals.cashback, "cashback")} />
                  <Kpi label="Canjeado en puntos" value={formatRewardValue(redeemedTotals.puntos, "puntos")} />
                </>
              )}
              <Kpi label="Productos promedio por factura" value={formatDecimal(data.summary.avg_items_per_receipt, 1)} />
              <Kpi label="Personas que aceptaron el estudio" value={formatInt(data.summary.consented_people)} />
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
                  detail: `${formatPercent(row.share)} · ${formatInt(row.receipts)} facturas · ticket ${formatMoney(row.avg_ticket)}`,
                }))}
              />
            </Section>

            <Section
              title="Ticket por rango"
              caption="Cuántas compras caen en cada rango de monto. Ayuda a fijar el valor de un combo o el valor en cashback de un producto canjeable."
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
              ariaLabel="Facturas por hora del día"
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

          <Section
            title="Compras por día del mes"
            caption="Cuántas facturas hay cada día del mes. En Panamá se cobra por quincena (el 15 y el 30): las columnas resaltadas muestran esos días y el siguiente, cuando suele subir el gasto."
            csv={`${exportBase}&section=month_days`}
          >
            <ColumnChart
              ariaLabel="Facturas por día del mes"
              highlight={(_, index) => [14, 15, 29, 30].includes(index)}
              items={Array.from({ length: 31 }, (_, index) => {
                const day = index + 1;
                const row = data.month_days.find((item) => num(item.day) === day);
                return {
                  label: String(day),
                  value: num(row?.receipts),
                  detail: `Día ${day} — ${formatInt(row?.receipts)} facturas · ${formatMoney(row?.total ?? null)} · ticket ${formatMoney(row?.avg_ticket ?? null)}`,
                };
              })}
            />
          </Section>

          <div className="insights-two">
            <Section
              title="Momento del día"
              caption="Facturas y ticket según el momento del día. Ayuda a elegir cuándo lanzar una promoción o una notificación."
              csv={`${exportBase}&section=dayparts`}
            >
              <BarList
                items={data.dayparts.map((row) => ({
                  label: row.daypart ?? "—",
                  value: num(row.receipts),
                  detail: `${formatInt(row.receipts)} facturas · ticket ${formatMoney(row.avg_ticket)}`,
                }))}
              />
            </Section>

            <Section
              title="Frecuencia de compra"
              caption="Cuántas veces compró cada persona en el periodo. Separa a los clientes ocasionales de los habituales."
              csv={`${exportBase}&section=frequency`}
            >
              <BarList
                items={data.frequency.map((row) => ({
                  label: row.bucket ?? "—",
                  value: num(row.people),
                  detail: `${formatInt(row.people)} personas`,
                }))}
              />
            </Section>
          </div>

          <Section
            title="Medio de pago por género"
            caption="Cómo paga cada grupo y su ticket promedio. Útil para campañas con bancos o tarjetas dirigidas a un público."
            csv={`${exportBase}&section=payment_by_gender`}
          >
            <PaymentByGender rows={data.payment_by_gender} />
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

          {ruc && (
            <Section
              title="Dónde más compran también sus clientes"
              caption="Otros comercios que visitan las personas que compran aquí, ordenados por cuántas personas comparten. Sirve para alianzas y para entender a la competencia."
              csv={`${exportBase}&section=also_shop_at`}
            >
              <BarList
                items={data.also_shop_at.map((row) => ({
                  label: row.merchant ?? `RUC ${row.ruc ?? "—"}`,
                  value: num(row.people),
                  detail: `${formatInt(row.people)} personas · ${formatInt(row.visits)} visitas · ${formatMoney(row.total)}`,
                }))}
              />
            </Section>
          )}

          <Section
            title="Productos canjeados"
            caption="Qué recompensas eligen las personas con su cashback o sus puntos. Indica qué tipo de producto atrae más visitas."
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
        Datos agregados y anónimos, solo de personas que aceptaron participar en el estudio. Ningún grupo con menos de{" "}
        {minUsers} personas se muestra.
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

function PaymentByGender({ rows }: { rows: { gender: string | null; method: string | null; receipts: unknown; people: unknown; avg_ticket: unknown }[] }) {
  if (rows.length === 0) return <p className="text-dim">Sin datos suficientes (ningún grupo llega a 5 personas).</p>;
  const genders = Array.from(new Set(rows.map((row) => row.gender ?? "sin_dato")));
  const methods = Array.from(new Set(rows.map((row) => row.method ?? "Otro"))).sort();
  const lookup = new Map(rows.map((row) => [`${row.gender ?? "sin_dato"}|${row.method ?? "Otro"}`, row]));
  return (
    <div className="table-scroll">
      <table>
        <thead>
          <tr>
            <th>Género</th>
            {methods.map((method) => (
              <th key={method}>{method}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {genders.map((gender) => (
            <tr key={gender}>
              <td>{GENDER_LABELS[gender] ?? gender}</td>
              {methods.map((method) => {
                const cell = lookup.get(`${gender}|${method}`);
                return (
                  <td key={method}>
                    {cell ? (
                      <>
                        {formatInt(cell.receipts)} facturas
                        <div className="text-dim">
                          {formatInt(cell.people)} personas · ticket {formatMoney(cell.avg_ticket)}
                        </div>
                      </>
                    ) : (
                      <span className="text-dim">—</span>
                    )}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
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

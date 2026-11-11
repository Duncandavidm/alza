import Link from "next/link";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { formatInt, formatMoney, num } from "@/lib/format";
import ActionForm from "@/components/ActionForm";
import { BarList, Kpi } from "@/components/Charts";
import { AI_FUNCTIONS, aiFunctionLabel } from "./functions";
import { updateAiSettings } from "./actions";

export const dynamic = "force-dynamic";

type AiCosts = {
  today_usd?: number | string;
  month_usd?: number | string;
  budget_usd?: number | string;
  calls_today?: number | string;
  by_function?: { function_name: string; calls: number | string; cached_hits: number | string; cost_usd: number | string }[];
  top_users?: { email: string | null; user_id: string | null; calls: number | string; cost_usd: number | string }[];
  by_day?: { day: string; cost_usd: number | string; calls: number | string }[];
};

type Quota = { limit?: number | string; period?: string };

/// Montos de IA: casi siempre son centavos o fracciones de centavo; si es
/// menor que $0.01 (y no es 0) se muestran 4 decimales para que no se lea "$0.00".
function formatUsd(value: unknown): string {
  const amount = num(value);
  if (amount > 0 && amount < 0.01) return `$${amount.toFixed(4)}`;
  return formatMoney(amount);
}

function formatDay(day: string): string {
  // "YYYY-MM-DD" ya viene en hora de Panama: se formatea como fecha UTC para no correrla un dia.
  return new Date(`${day}T00:00:00Z`).toLocaleDateString("es-PA", { timeZone: "UTC", weekday: "short", day: "numeric", month: "short" });
}

// Costo de IA (RPC admin_ai_costs, solo service role): gasto de hoy y del
// mes, por funcion, por cliente y por dia, mas el tope diario y las cuotas.
export default async function IaPage() {
  const supabase = supabaseAdmin();
  const [{ data, error }, { data: quotaRow }] = await Promise.all([
    supabase.rpc("admin_ai_costs"),
    supabase.from("app_config").select("value").eq("key", "ai_quotas").maybeSingle<{ value: Record<string, Quota> | null }>(),
  ]);
  const costs = (data ?? {}) as AiCosts;
  const today = num(costs.today_usd);
  const month = num(costs.month_usd);
  const budget = num(costs.budget_usd) || 5;
  const usedPct = budget > 0 ? (today / budget) * 100 : 0;
  const nearLimit = usedPct >= 80;
  const paused = today >= budget;
  const byFunction = costs.by_function ?? [];
  const topUsers = costs.top_users ?? [];
  const byDay = costs.by_day ?? [];
  const quotas = quotaRow?.value ?? {};

  return (
    <>
      <h1 style={{ marginBottom: 4 }}>Costo de IA</h1>
      <p className="text-dim">Gasto en Claude de las funciones de IA de la app (hora de Panamá).</p>

      {error ? (
        <div className="card">
          <p className="error" style={{ margin: 0 }}>No se pudo leer el costo de IA: {error.message}</p>
        </div>
      ) : (
        <>
          {paused && (
            <div className="card" style={{ borderColor: "var(--danger)", color: "var(--danger)" }}>
              <strong>Las funciones de IA están en pausa hasta mañana porque se alcanzó el tope diario.</strong>
            </div>
          )}

          <div className="card">
            <div className="kpi-grid">
              <div className="kpi">
                <div className="text-dim">Hoy</div>
                <div className="kpi-value" style={nearLimit ? { color: "var(--danger)" } : undefined}>
                  {formatMoney(today)}
                </div>
                <div className="text-dim kpi-hint">de {formatMoney(budget)} de tope diario</div>
                <div className="bar-track" style={{ marginTop: 8, background: "var(--border)" }}>
                  <div
                    className="bar-fill"
                    style={{
                      width: `${Math.min(100, Math.max(usedPct, today > 0 ? 1.5 : 0))}%`,
                      background: nearLimit ? "var(--danger)" : undefined,
                    }}
                  />
                </div>
              </div>
              <Kpi label="Este mes" value={formatMoney(month)} />
              <Kpi label="Llamadas hoy" value={formatInt(costs.calls_today)} hint="Sin contar resultados guardados" />
            </div>
          </div>

          <div className="card">
            <h3>Por función</h3>
            <p className="text-dim">Este mes.</p>
            {byFunction.length === 0 ? (
              <p className="text-dim">Todavía no hay uso de IA este mes.</p>
            ) : (
              <div className="table-scroll">
                <table>
                  <thead>
                    <tr>
                      <th>Función</th>
                      <th>Llamadas</th>
                      <th>Resultados guardados</th>
                      <th>Costo</th>
                    </tr>
                  </thead>
                  <tbody>
                    {byFunction.map((row) => (
                      <tr key={row.function_name}>
                        <td>{aiFunctionLabel(row.function_name)}</td>
                        <td>{formatInt(row.calls)}</td>
                        <td>{formatInt(row.cached_hits)}</td>
                        <td>{formatUsd(row.cost_usd)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          <div className="card">
            <h3>Clientes que más gastan este mes</h3>
            {topUsers.length === 0 ? (
              <p className="text-dim">Todavía no hay uso de IA este mes.</p>
            ) : (
              <div className="table-scroll">
                <table>
                  <thead>
                    <tr>
                      <th>Cliente</th>
                      <th>Llamadas</th>
                      <th>Costo</th>
                    </tr>
                  </thead>
                  <tbody>
                    {topUsers.map((row, index) => (
                      <tr key={row.user_id ?? `sin-usuario-${index}`}>
                        <td>
                          {row.user_id ? (
                            <Link href={`/clientes/${row.user_id}`}>{row.email ?? row.user_id}</Link>
                          ) : (
                            <span className="text-dim">{row.email ?? "Sin cuenta (borrada)"}</span>
                          )}
                        </td>
                        <td>{formatInt(row.calls)}</td>
                        <td>{formatUsd(row.cost_usd)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          <div className="card">
            <h3>Últimos 30 días</h3>
            <p className="text-dim">Costo por día.</p>
            <BarList
              items={byDay.map((row) => ({
                label: formatDay(row.day),
                value: num(row.cost_usd),
                detail: `${formatUsd(row.cost_usd)} · ${formatInt(row.calls)} ${num(row.calls) === 1 ? "llamada" : "llamadas"}`,
              }))}
              emptyText="Todavía no hay uso de IA en los últimos 30 días."
            />
          </div>
        </>
      )}

      <div className="card">
        <h3>Tope y cuotas</h3>
        <p className="text-dim">
          Si el gasto de hoy llega al tope diario, las funciones de IA se pausan hasta mañana. Cada cuota es por persona; los
          resultados guardados no cuentan.
        </p>
        <ActionForm action={updateAiSettings} className="grid-form" submitLabel="Guardar">
          <div className="field">
            <label htmlFor="budget_usd">Tope diario (US$)</label>
            <input id="budget_usd" type="number" name="budget_usd" defaultValue={budget} min={0.5} max={1000} step="0.01" required />
          </div>
          {AI_FUNCTIONS.map((fn) => {
            const quota = quotas[fn.key] ?? {};
            const period = quota.period ?? fn.defaultPeriod;
            const limit = quota.limit === undefined || quota.limit === null ? fn.defaultLimit : num(quota.limit);
            return (
              <div className="field" key={fn.key}>
                <label htmlFor={`limit_${fn.key}`}>
                  {fn.label} ({period === "day" ? "por día" : "por mes"})
                </label>
                <input
                  id={`limit_${fn.key}`}
                  type="number"
                  name={`limit_${fn.key}`}
                  defaultValue={limit}
                  min={0}
                  max={10000}
                  step="1"
                  required
                />
              </div>
            );
          })}
        </ActionForm>
      </div>
    </>
  );
}

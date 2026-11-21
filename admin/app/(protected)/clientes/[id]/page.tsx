import Link from "next/link";
import { notFound } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { parseUuid, cleanLine } from "@/lib/push";
import { formatCashback, formatDate, formatDateTime, formatInt, formatMoney } from "@/lib/format";
import { LIFETIME_PRODUCT_ID, canResetAccount, isBanned, isProtectedEmail } from "@/lib/customer-accounts";
import { Kpi } from "@/components/Charts";
import { deleteCustomer, resetCustomer, setCustomerSuspended, setLifetimeAccess } from "./actions";

type MonthMetrics = {
  month: string;
  income: number;
  expenses: number;
  savings_rate: number | null;
  logged_days: number;
  budgets: number;
  budgets_met: number;
  receipts: number;
  overdue_bills: number;
  score: number;
};

type Health = {
  last_month: MonthMetrics;
  this_month: MonthMetrics;
  goals: { name: string; target: number; current: number; target_date: string | null }[];
  coupons: number;
};

function HealthMonth({ title, metrics }: { title: string; metrics: MonthMetrics }) {
  return (
    <>
      <h4 style={{ margin: "12px 0 6px" }}>
        {title} ({metrics.month})
      </h4>
      <div className="kpi-grid">
        <Kpi label="Salud financiera" value={`${metrics.score} / 100`} />
        <Kpi label="Ahorro" value={metrics.savings_rate === null ? "—" : `${metrics.savings_rate}%`} hint="de sus ingresos" />
        <Kpi label="Ingresos" value={formatMoney(metrics.income)} />
        <Kpi label="Gastos" value={formatMoney(metrics.expenses)} />
        <Kpi label="Días anotados" value={formatInt(metrics.logged_days)} />
        <Kpi label="Presupuestos cumplidos" value={`${metrics.budgets_met} de ${metrics.budgets}`} />
        <Kpi label="Facturas escaneadas" value={formatInt(metrics.receipts)} />
        <Kpi label="Cuentas vencidas" value={formatInt(metrics.overdue_bills)} />
      </div>
    </>
  );
}

export const dynamic = "force-dynamic";

type CustomerRow = {
  id: string;
  full_name: string | null;
  phone: string | null;
  transactions: number | string | null;
  receipts: number | string | null;
  cashback_cents: number | string | null;
  points: number | string | null;
  redemptions: number | string | null;
  subscription: string | null;
};

function first(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

// Gestion de una cuenta de cliente: suspender, reactivar o eliminar.
export default async function ClienteDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { id: rawId } = await params;
  const query = await searchParams;
  const id = parseUuid(rawId);
  if (!id) notFound();

  const supabase = supabaseAdmin();
  const { data: userData, error: userError } = await supabase.auth.admin.getUserById(id);
  const user = userData?.user;
  if (!user) {
    if (userError && userError.status !== 404) {
      return <p className="error">No se pudo leer la cuenta: {userError.message}</p>;
    }
    notFound();
  }

  // Estadisticas y suscripcion desde admin_customers (busqueda por correo).
  let row: CustomerRow | undefined;
  if (user.email) {
    const { data } = await supabase.rpc("admin_customers", { p_search: user.email, p_limit: 50, p_offset: 0 });
    row = ((data ?? {}) as { rows?: CustomerRow[] }).rows?.find((r) => r.id === id);
  }

  const { data: sub } = await supabase
    .from("subscriptions")
    .select("product_id, status, expires_at, apple_original_transaction_id")
    .eq("user_id", id)
    .maybeSingle();
  const hasLifetime = sub?.product_id === LIFETIME_PRODUCT_ID && sub.status === "active";
  const paysWithApple = Boolean(sub?.apple_original_transaction_id) && sub?.status === "active";

  const { data: healthData } = await supabase.rpc("admin_financial_health", { p_user_id: id });
  const health = (healthData ?? null) as Health | null;

  const banned = isBanned(user.banned_until);
  const isProtected = isProtectedEmail(user.email);
  const hasActiveSubscription = row?.subscription === "active";
  const message = cleanLine(first(query.msg), 400);
  const errorMessage = cleanLine(first(query.err), 400);

  return (
    <>
      <p style={{ margin: "0 0 8px" }}>
        <Link href="/clientes">← Clientes</Link>
      </p>
      <div className="insights-head">
        <div>
          <h1 style={{ marginBottom: 4 }}>
            {row?.full_name || "Sin nombre"}{" "}
            {banned && <span className="badge rechazada">Suspendida</span>}
          </h1>
          <p className="text-dim" style={{ margin: 0 }}>
            {user.email ?? "Sin correo"}
            {row?.phone ? ` · ${row.phone}` : ""}
          </p>
        </div>
        <span className="pii-note">🔒 Datos personales: no compartir</span>
      </div>

      {message && (
        <div className="card">
          <strong className="success-text">Listo.</strong> {message}
        </div>
      )}
      {errorMessage && (
        <div className="card">
          <p className="error" style={{ margin: 0 }}>{errorMessage}</p>
        </div>
      )}

      <div className="card">
        <h2 style={{ marginTop: 0 }}>Cuenta</h2>
        <p style={{ margin: "4px 0" }}>Registro: {formatDate(user.created_at)}</p>
        <p style={{ margin: "4px 0" }}>Último ingreso: {formatDateTime(user.last_sign_in_at ?? null)}</p>
        {row && (
          <p className="text-dim" style={{ margin: "4px 0" }}>
            {formatInt(row.transactions)} movimientos · {formatInt(row.receipts)} facturas ·{" "}
            {formatCashback(row.cashback_cents)} cashback · {formatInt(row.points)} puntos · {formatInt(row.redemptions)} canjes
            {row.subscription ? ` · Suscripción: ${row.subscription}` : ""}
          </p>
        )}
        <p style={{ margin: "4px 0" }}>
          Estado:{" "}
          {banned ? (
            <span className="badge rechazada">Suspendida</span>
          ) : (
            <span className="badge active">Activa</span>
          )}
        </p>
      </div>

      <div className="card">
        <h2 style={{ marginTop: 0 }}>Acceso Pro de por vida</h2>
        {hasLifetime ? (
          <>
            <p>
              <span className="badge active">Activo</span> Tiene MonAvi Pro sin pagar y sin vencimiento.
            </p>
            {!isProtected && (
              <form action={setLifetimeAccess}>
                <input type="hidden" name="id" value={id} />
                <input type="hidden" name="grant" value="0" />
                <button type="submit" className="secondary">Quitar acceso de por vida</button>
              </form>
            )}
          </>
        ) : paysWithApple ? (
          <p className="text-dim" style={{ margin: 0 }}>
            Ya tiene una suscripción activa pagada por Apple ({sub?.product_id}). Para darle acceso de por vida, primero
            debe cancelarla en su iPhone y esperar a que venza.
          </p>
        ) : (
          <>
            <p className="text-dim">
              Le da MonAvi Pro gratis y sin vencimiento (por ejemplo, a tu equipo, aliados o ganadores de un concurso). No
              es una compra de Apple y se puede quitar cuando quieras.
            </p>
            <form action={setLifetimeAccess}>
              <input type="hidden" name="id" value={id} />
              <input type="hidden" name="grant" value="1" />
              <button type="submit">Dar acceso de por vida</button>
            </form>
          </>
        )}
      </div>

      {health && (
        <div className="card">
          <h2 style={{ marginTop: 0 }}>Salud financiera</h2>
          <p className="text-dim">
            Sale de lo que registra en la app. Es lo que usan las reglas de <Link href="/cupones">cupones por buenos hábitos</Link>.
            Cupones ganados: {formatInt(health.coupons)}.
          </p>
          <HealthMonth title="Mes pasado" metrics={health.last_month} />
          <HealthMonth title="Este mes" metrics={health.this_month} />
          {health.goals.length > 0 && (
            <>
              <h4 style={{ margin: "12px 0 6px" }}>Metas de ahorro</h4>
              <ul>
                {health.goals.map((goal) => (
                  <li key={goal.name}>
                    {goal.name}: {formatMoney(goal.current)} de {formatMoney(goal.target)}
                    {goal.target_date ? ` · para el ${formatDate(goal.target_date)}` : ""}
                  </li>
                ))}
              </ul>
            </>
          )}
        </div>
      )}

      {canResetAccount(user.email) && user.email && (
        <div className="card">
          <h2 style={{ marginTop: 0 }}>Reiniciar cuenta</h2>
          <p className="text-dim">
            Deja la cuenta como nueva: borra movimientos, cuentas, metas, presupuestos, facturas, cashback y canjes, y la
            próxima vez que entre verá el onboarding. La cuenta, el correo y la suscripción se quedan.
          </p>
          <form action={resetCustomer} className="inline-actions">
            <input type="hidden" name="id" value={id} />
            <input
              type="email"
              name="confirm_email"
              required
              autoComplete="off"
              placeholder={`Escribe ${user.email} para confirmar`}
              aria-label="Correo del cliente para confirmar el reinicio"
              style={{ flex: "1 1 260px" }}
            />
            <button type="submit" className="danger">
              Reiniciar cuenta
            </button>
          </form>
        </div>
      )}

      {isProtected ? (
        <div className="card">
          <p className="text-dim" style={{ margin: 0 }}>
            Esta es una cuenta protegida (demo / revisión de Apple): no se puede suspender ni eliminar desde el panel.
          </p>
        </div>
      ) : (
        <>
          <div className="card">
            <h2 style={{ marginTop: 0 }}>{banned ? "Reactivar cuenta" : "Suspender cuenta"}</h2>
            <p className="text-dim">
              {banned
                ? "La persona podrá volver a iniciar sesión con su cuenta y sus datos intactos."
                : "La persona no podrá iniciar sesión ni renovar su sesión. Sus datos no se borran y se puede reactivar después."}
            </p>
            <form action={setCustomerSuspended}>
              <input type="hidden" name="id" value={id} />
              <input type="hidden" name="suspend" value={banned ? "0" : "1"} />
              <button type="submit" className={banned ? undefined : "secondary"}>
                {banned ? "Reactivar" : "Suspender"}
              </button>
            </form>
          </div>

          <div className="card" style={{ borderColor: "var(--danger)" }}>
            <h2 style={{ marginTop: 0 }}>Eliminar cuenta</h2>
            <p className="error">
              Se borran para siempre sus movimientos, metas, facturas, cashback y canjes. No se puede deshacer.
            </p>
            {hasActiveSubscription && (
              <p className="error">
                <strong>Atención:</strong> Esta persona tiene una suscripción activa en Apple: eliminar su cuenta no cancela
                el cobro; debe cancelarla en Ajustes de su iPhone.
              </p>
            )}
            {user.email ? (
              <form action={deleteCustomer} className="inline-actions">
                <input type="hidden" name="id" value={id} />
                <input
                  type="email"
                  name="confirm_email"
                  required
                  autoComplete="off"
                  placeholder={`Escribe ${user.email} para confirmar`}
                  aria-label="Correo del cliente para confirmar"
                  style={{ flex: "1 1 260px" }}
                />
                <button type="submit" className="danger">
                  Eliminar cuenta
                </button>
              </form>
            ) : (
              <p className="text-dim">La cuenta no tiene correo: no se puede confirmar el borrado desde el panel.</p>
            )}
          </div>
        </>
      )}
    </>
  );
}

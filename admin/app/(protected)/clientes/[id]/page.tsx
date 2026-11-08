import Link from "next/link";
import { notFound } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { parseUuid, cleanLine } from "@/lib/push";
import { formatCashback, formatDate, formatDateTime, formatInt } from "@/lib/format";
import { isBanned, isProtectedEmail } from "@/lib/customer-accounts";
import { deleteCustomer, setCustomerSuspended } from "./actions";

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
              Se borran para siempre sus movimientos, metas, facturas, cashback, puntos y canjes. No se puede deshacer.
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

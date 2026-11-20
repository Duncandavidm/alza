import Link from "next/link";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { formatCashback, formatDate, formatDateTime, formatInt, num } from "@/lib/format";
import { cleanLine } from "@/lib/push";
import { bannedUntilByIds, isBanned } from "@/lib/customer-accounts";

export const dynamic = "force-dynamic";

const PAGE_SIZE = 50;

type Customer = {
  id: string;
  email: string | null;
  created_at: string | null;
  last_sign_in_at: string | null;
  full_name: string | null;
  phone: string | null;
  gender: string | null;
  age: number | null;
  occupation: string | null;
  last_activity: string | null;
  transactions: number | string | null;
  receipts: number | string | null;
  cashback_cents: number | string | null;
  points: number | string | null;
  redemptions: number | string | null;
  has_push: boolean | null;
  consents: Record<string, boolean> | null;
  subscription: string | null;
};

const CONSENT_BADGES: { purpose: string; label: string }[] = [
  { purpose: "estudio_mercado", label: "Estudio" },
  { purpose: "ofertas", label: "Ofertas" },
];

function first(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

// Clientes de la app (RPC admin_customers, solo service role). Contiene
// datos personales: solo para soporte y operacion interna.
export default async function ClientesPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const search = (first(params.q) ?? "").replace(/\s+/g, " ").trim().slice(0, 80);
  const pageNumber = Math.max(1, Math.min(10000, Math.floor(Number(first(params.page)) || 1)));

  const message = cleanLine(first(params.msg), 400);
  const errorMessage = cleanLine(first(params.err), 400);
  const supabase = supabaseAdmin();
  const { data, error } = await supabase.rpc("admin_customers", {
    p_search: search || null,
    p_limit: PAGE_SIZE,
    p_offset: (pageNumber - 1) * PAGE_SIZE,
  });
  const result = (data ?? {}) as { total?: number | string; rows?: Customer[] };
  const total = num(result.total);
  const rows = result.rows ?? [];
  const bannedUntil = await bannedUntilByIds(
    supabase,
    rows.map((row) => row.id)
  );
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  const pageHref = (page: number) => {
    const query = new URLSearchParams();
    if (search) query.set("q", search);
    if (page > 1) query.set("page", String(page));
    const text = query.toString();
    return text ? `/clientes?${text}` : "/clientes";
  };

  return (
    <>
      <div className="insights-head">
        <div>
          <h1 style={{ marginBottom: 4 }}>Clientes</h1>
          <p className="text-dim" style={{ margin: 0 }}>
            {formatInt(total)} {total === 1 ? "cuenta" : "cuentas"}
            {search ? ` que coinciden con “${search}”` : ""}
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

      <form method="get" action="/clientes" className="card inline-actions">
        <input
          type="text"
          name="q"
          defaultValue={search}
          placeholder="Buscar por correo, nombre o teléfono"
          style={{ flex: "1 1 260px" }}
          aria-label="Buscar cliente"
        />
        <button type="submit">Buscar</button>
        {search && (
          <Link href="/clientes" className="button secondary-link">
            Limpiar
          </Link>
        )}
      </form>

      <div className="card">
        {error ? (
          <p className="error">No se pudo leer la lista de clientes: {error.message}</p>
        ) : rows.length === 0 ? (
          <p className="text-dim">{search ? "Nadie coincide con esa búsqueda." : "Todavía no hay clientes."}</p>
        ) : (
          <div className="table-scroll">
            <table className="customers-table">
              <thead>
                <tr>
                  <th>Cliente</th>
                  <th>Teléfono</th>
                  <th>Registro</th>
                  <th>Última actividad</th>
                  <th>Movimientos</th>
                  <th>Facturas</th>
                  <th>Cashback</th>
                  <th>Puntos</th>
                  <th>Canjes</th>
                  <th>Push</th>
                  <th>Permisos</th>
                  <th>Suscripción</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => (
                  <tr key={row.id}>
                    <td>
                      <strong>{row.full_name || "Sin nombre"}</strong>
                      {isBanned(bannedUntil.get(row.id)) && (
                        <>
                          {" "}
                          <span className="badge rechazada">Suspendida</span>
                        </>
                      )}
                      <div className="text-dim">{row.email ?? "—"}</div>
                      {(row.gender || row.age || row.occupation) && (
                        <div className="text-dim">
                          {[row.gender, row.age ? `${row.age} años` : null, row.occupation].filter(Boolean).join(" · ")}
                        </div>
                      )}
                    </td>
                    <td style={{ whiteSpace: "nowrap" }}>{row.phone || "—"}</td>
                    <td style={{ whiteSpace: "nowrap" }}>{formatDate(row.created_at)}</td>
                    <td style={{ whiteSpace: "nowrap" }}>
                      {formatDateTime(row.last_activity)}
                      {row.last_sign_in_at && <div className="text-dim">Entró {formatDate(row.last_sign_in_at)}</div>}
                    </td>
                    <td>{formatInt(row.transactions)}</td>
                    <td>{formatInt(row.receipts)}</td>
                    <td>{formatCashback(row.cashback_cents)}</td>
                    <td>{formatInt(row.points)}</td>
                    <td>{formatInt(row.redemptions)}</td>
                    <td>{row.has_push ? <span className="badge active">Sí</span> : <span className="text-dim">No</span>}</td>
                    <td>
                      <div className="inline-actions" style={{ gap: 4 }}>
                        {CONSENT_BADGES.map((consent) => {
                          const granted = row.consents?.[consent.purpose] === true;
                          return (
                            <span
                              key={consent.purpose}
                              className={`badge ${granted ? "active" : "expirada"}`}
                              title={granted ? "Aceptado" : "No aceptado"}
                            >
                              {granted ? "✓" : "✗"} {consent.label}
                            </span>
                          );
                        })}
                      </div>
                    </td>
                    <td>{row.subscription ? <span className="badge">{row.subscription}</span> : <span className="text-dim">—</span>}</td>
                    <td>
                      <Link href={`/clientes/${row.id}`}>Gestionar</Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {pages > 1 && (
          <div className="inline-actions" style={{ marginTop: 14, justifyContent: "space-between" }}>
            {pageNumber > 1 ? <Link href={pageHref(pageNumber - 1)}>← Anterior</Link> : <span />}
            <span className="text-dim">
              Página {formatInt(pageNumber)} de {formatInt(pages)}
            </span>
            {pageNumber < pages ? <Link href={pageHref(pageNumber + 1)}>Siguiente →</Link> : <span />}
          </div>
        )}
      </div>
    </>
  );
}

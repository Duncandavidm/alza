import Link from "next/link";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { embedded, formatDateTime, formatPoints } from "@/lib/format";
import ActionForm from "@/components/ActionForm";
import { cancelRedemption, markRedemptionDelivered } from "./actions";

const STATUSES = ["emitido", "entregado", "cancelado", "vencido"] as const;
type RedemptionStatus = (typeof STATUSES)[number];

type Redemption = {
  id: string;
  code: string;
  status: RedemptionStatus;
  points_cost: number;
  expires_at: string;
  delivered_at: string | null;
  created_at: string;
  merchant_id: string;
  reward_items: { name: string } | { name: string }[] | null;
  partner_merchants: { name: string } | { name: string }[] | null;
};

function panamaDate(date: Date): string {
  return date.toLocaleDateString("en-CA", { timeZone: "America/Panama" });
}

export default async function RedemptionsPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; status?: string; merchant?: string }>;
}) {
  const params = await searchParams;
  const q = (params.q ?? "").trim().toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 12);
  const status = (STATUSES as readonly string[]).includes(params.status ?? "") ? (params.status as RedemptionStatus) : null;
  const merchantId = /^[0-9a-f-]{36}$/i.test(params.merchant ?? "") ? params.merchant! : null;

  const supabase = supabaseAdmin();
  let query = supabase
    .from("reward_redemptions")
    .select(
      "id, code, status, points_cost, expires_at, delivered_at, created_at, merchant_id, reward_items(name), partner_merchants(name)"
    )
    .order("created_at", { ascending: false })
    .limit(200);
  if (q) query = query.ilike("code", `%${q}%`);
  if (status) query = query.eq("status", status);
  if (merchantId) query = query.eq("merchant_id", merchantId);

  const nowIso = new Date().toISOString();
  const [{ data: redemptions, error }, { data: merchants }, { count: pendingCount }, { count: overdueCount }] =
    await Promise.all([
      query.returns<Redemption[]>(),
      supabase.from("partner_merchants").select("id, name").order("name").returns<{ id: string; name: string }[]>(),
      supabase
        .from("reward_redemptions")
        .select("id", { count: "exact", head: true })
        .eq("status", "emitido")
        .gt("expires_at", nowIso),
      supabase
        .from("reward_redemptions")
        .select("id", { count: "exact", head: true })
        .eq("status", "emitido")
        .lte("expires_at", nowIso),
    ]);

  const now = new Date();
  const today = panamaDate(now);

  return (
    <>
      <h1>Canjes</h1>
      <p className="text-dim">
        Cada canje genera un código de 6 caracteres que el cliente muestra en caja. Cuando el comercio entrega el producto,
        márcalo como entregado. Los canjes que no se entregan vencen a los 7 días y un proceso nocturno los libera y devuelve
        los puntos.
      </p>

      <div className="grid-form" style={{ marginBottom: 16 }}>
        <div className="card" style={{ marginBottom: 0 }}>
          <div className="text-dim">Por entregar</div>
          <div className="stat-value">{pendingCount ?? 0}</div>
        </div>
        <div className="card" style={{ marginBottom: 0 }}>
          <div className="text-dim">Vencidos sin liberar (se liberan esta noche)</div>
          <div className="stat-value" style={{ color: (overdueCount ?? 0) > 0 ? "var(--warning)" : undefined }}>
            {overdueCount ?? 0}
          </div>
        </div>
      </div>

      <form className="card grid-form" method="get">
        <div className="field">
          <label>Código</label>
          <input type="text" name="q" defaultValue={q} placeholder="ABC123" maxLength={12} style={{ textTransform: "uppercase" }} />
        </div>
        <div className="field">
          <label>Estado</label>
          <select name="status" defaultValue={status ?? ""}>
            <option value="">Todos</option>
            {STATUSES.map((value) => (
              <option key={value} value={value}>
                {value}
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label>Comercio</label>
          <select name="merchant" defaultValue={merchantId ?? ""}>
            <option value="">Todos</option>
            {(merchants ?? []).map((merchant) => (
              <option key={merchant.id} value={merchant.id}>
                {merchant.name}
              </option>
            ))}
          </select>
        </div>
        <div className="field" style={{ alignSelf: "end", display: "flex", gap: 8 }}>
          <button type="submit">Buscar</button>
          <Link href="/redemptions" className="button secondary-link">
            Limpiar
          </Link>
        </div>
      </form>

      <div className="card table-scroll">
        {error && <p className="error">No se pudieron leer los canjes: {error.message}</p>}
        <table>
          <thead>
            <tr>
              <th>Código</th>
              <th>Producto</th>
              <th>Comercio</th>
              <th>Puntos</th>
              <th>Creado</th>
              <th>Vence / entregado</th>
              <th>Estado</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {(redemptions ?? []).map((redemption) => {
              const expiresAt = new Date(redemption.expires_at);
              const isEmitted = redemption.status === "emitido";
              const isOverdue = isEmitted && expiresAt <= now;
              const expiresToday = isEmitted && !isOverdue && panamaDate(expiresAt) === today;
              const canAct = isEmitted && !isOverdue;

              return (
                <tr key={redemption.id} className={isOverdue ? "row-dim" : undefined}>
                  <td>
                    <code className="code">{redemption.code}</code>
                  </td>
                  <td>{embedded(redemption.reward_items)?.name ?? "—"}</td>
                  <td>
                    <Link href={`/merchants/${redemption.merchant_id}`}>{embedded(redemption.partner_merchants)?.name ?? "—"}</Link>
                  </td>
                  <td>{formatPoints(redemption.points_cost)}</td>
                  <td className="text-dim">{formatDateTime(redemption.created_at)}</td>
                  <td className="text-dim">
                    {redemption.status === "entregado"
                      ? `Entregado ${formatDateTime(redemption.delivered_at)}`
                      : formatDateTime(redemption.expires_at)}
                  </td>
                  <td>
                    {isOverdue ? (
                      <span className="badge vencido" title="El proceso nocturno lo libera y devuelve los puntos">
                        vencido (por liberar)
                      </span>
                    ) : expiresToday ? (
                      <span className="badge paused">vence hoy</span>
                    ) : (
                      <span className={`badge ${redemption.status}`}>{redemption.status}</span>
                    )}
                  </td>
                  <td>
                    {canAct && (
                      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                        <ActionForm
                          action={markRedemptionDelivered.bind(null, redemption.id)}
                          confirm={`¿Marcar ${redemption.code} como entregado?`}
                          submitLabel="Marcar entregado"
                          pendingLabel="Guardando…"
                          inline
                        >
                          {null}
                        </ActionForm>
                        <ActionForm
                          action={cancelRedemption.bind(null, redemption.id)}
                          confirm={`¿Cancelar ${redemption.code} y devolver ${redemption.points_cost} puntos al cliente?`}
                          submitLabel="Cancelar y devolver puntos"
                          submitClassName="danger"
                          pendingLabel="Cancelando…"
                          inline
                        >
                          {null}
                        </ActionForm>
                      </div>
                    )}
                  </td>
                </tr>
              );
            })}
            {(redemptions ?? []).length === 0 && !error && (
              <tr>
                <td colSpan={8} className="text-dim">
                  {q || status || merchantId ? "Ningún canje coincide con la búsqueda." : "Todavía no hay canjes."}
                </td>
              </tr>
            )}
          </tbody>
        </table>
        {(redemptions ?? []).length === 200 && (
          <p className="text-dim">Mostrando los 200 más recientes. Usa los filtros para acotar.</p>
        )}
      </div>
    </>
  );
}

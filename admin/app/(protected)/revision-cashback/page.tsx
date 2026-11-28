import { supabaseAdmin } from "@/lib/supabase-admin";
import { resolveReview } from "./actions";

export const dynamic = "force-dynamic";

type Review = {
  id: string;
  user_id: string;
  reason: string;
  details: Record<string, unknown>;
  status: string;
  note: string | null;
  created_at: string;
  resolved_at: string | null;
};

const REASONS: Record<string, string> = {
  ingreso_inusual: "Ingreso inusual (más del doble de su promedio)",
  ingreso_a_la_medida: "Ingreso justo del monto que faltaba para liberar cashback",
  ingreso_editado: "Ingreso editado o borrado después de liberar cashback",
  muchas_facturas: "Muchas facturas de comercios distintos en pocas horas",
  dispositivo_compartido: "Varias cuentas en el mismo iPhone",
  telefono_repetido: "Teléfono repetido en otra cuenta",
  manual: "Revisión manual",
};

const money = (value: unknown) =>
  typeof value === "number" || (typeof value === "string" && value !== "")
    ? "$" + Number(value).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
    : "—";

function detailText(review: Review): string {
  const d = review.details ?? {};
  switch (review.reason) {
    case "ingreso_inusual":
      return `Ingreso de ${money(d.amount)}; su promedio mensual es ${money(d.monthly_average)}.`;
    case "ingreso_a_la_medida":
      return `Ingreso de ${money(d.amount)} con ${money(d.held_purchases)} en compras con cashback retenido.`;
    case "ingreso_editado":
      return `Antes ${money(d.old_amount)}, ahora ${d.new_amount == null ? "borrado" : money(d.new_amount)}.`;
    case "muchas_facturas":
      return `${d.receipts_3h} facturas de ${d.merchants_3h} comercios en 3 horas.`;
    case "dispositivo_compartido":
      return `${d.accounts_on_device} cuentas en el mismo iPhone.`;
    case "telefono_repetido":
      return `Teléfono terminado en ${d.phone_tail}.`;
    default:
      return "";
  }
}

export default async function CashbackReviewPage() {
  const supabase = supabaseAdmin();
  const { data } = await supabase
    .from("cashback_reviews")
    .select("*")
    .order("status", { ascending: true })
    .order("created_at", { ascending: false })
    .limit(200);
  const reviews = (data ?? []) as Review[];
  const userIds = [...new Set(reviews.map((r) => r.user_id))];

  const [{ data: profiles }, { data: held }] = await Promise.all([
    userIds.length
      ? supabase.from("profiles").select("id, full_name, country, verified_income, verified_income_until").in("id", userIds)
      : Promise.resolve({ data: [] }),
    userIds.length
      ? supabase.from("dgi_receipts").select("user_id, confirmed_amount").in("user_id", userIds).eq("cashback_status", "sin_ingreso")
      : Promise.resolve({ data: [] }),
  ]);
  const profileById = new Map((profiles ?? []).map((p: { id: string }) => [p.id, p as Record<string, unknown>]));
  const heldByUser = new Map<string, number>();
  for (const row of (held ?? []) as { user_id: string; confirmed_amount: number | null }[]) {
    heldByUser.set(row.user_id, (heldByUser.get(row.user_id) ?? 0) + Number(row.confirmed_amount ?? 0));
  }

  const open = reviews.filter((r) => r.status === "abierta");
  const closed = reviews.filter((r) => r.status !== "abierta");

  return (
    <>
      <h1>Revisión de cashback</h1>
      <p className="text-dim">
        Cuando la app detecta un patrón raro con los ingresos o las facturas de alguien, abre una revisión: su cashback
        nuevo queda retenido (en la app se ve como pendiente) hasta que la resuelvas. <b>Aprobar</b> deja que el sistema
        lo libere si sus ingresos lo respaldan (tope sin verificar: $3,000 al mes). <b>Anular</b> cancela el cashback
        retenido de esa persona. La cuenta y sus datos no se tocan.
      </p>

      <h2>Abiertas ({open.length})</h2>
      {open.length === 0 && <p className="text-dim">No hay revisiones abiertas.</p>}
      {open.map((review) => {
        const profile = profileById.get(review.user_id) ?? {};
        return (
          <div className="card" key={review.id}>
            <h3>{REASONS[review.reason] ?? review.reason}</h3>
            <p>
              <b>{String(profile.full_name ?? "Sin nombre")}</b> · {String(profile.country ?? "PA")} ·{" "}
              <a href={`/clientes/${review.user_id}`}>ver cliente</a>
            </p>
            <p className="text-dim">{detailText(review)}</p>
            <p className="text-dim">
              Compras con cashback retenido: {money(heldByUser.get(review.user_id) ?? 0)}
              {profile.verified_income ? ` · Ingreso verificado: ${money(profile.verified_income)} hasta ${profile.verified_income_until}` : ""}
              {" · "}Abierta el {new Date(review.created_at).toLocaleString("es-PA", { timeZone: "America/Panama" })}
            </p>
            <form style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
              <input name="note" placeholder="Nota (opcional)" style={{ flex: 1, minWidth: 200 }} />
              <button formAction={resolveReview.bind(null, review.id, true)}>Aprobar</button>
              <button className="danger" formAction={resolveReview.bind(null, review.id, false)}>Anular cashback retenido</button>
            </form>
          </div>
        );
      })}

      <h2>Resueltas</h2>
      {closed.length === 0 && <p className="text-dim">Todavía no hay revisiones resueltas.</p>}
      {closed.length > 0 && (
        <table>
          <thead>
            <tr><th>Motivo</th><th>Cliente</th><th>Resultado</th><th>Nota</th><th>Fecha</th></tr>
          </thead>
          <tbody>
            {closed.map((review) => (
              <tr key={review.id}>
                <td>{REASONS[review.reason] ?? review.reason}</td>
                <td>{String(profileById.get(review.user_id)?.full_name ?? review.user_id.slice(0, 8))}</td>
                <td><span className={`badge ${review.status === "aprobada" ? "active" : "paused"}`}>{review.status}</span></td>
                <td>{review.note ?? ""}</td>
                <td>{review.resolved_at ? new Date(review.resolved_at).toLocaleDateString("es-PA") : ""}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </>
  );
}

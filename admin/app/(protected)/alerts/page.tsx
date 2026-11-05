import { supabaseAdmin } from "@/lib/supabase-admin";

type AmbiguousRow = {
  id: string;
  merchant_ruc: string;
  amount: number;
  card_last4: string;
  card_brand: string;
  occurred_at: string;
  match_note: string | null;
};
type UnmatchedBankRow = {
  id: string;
  external_account_ref: string;
  period_month: string;
  avg_balance: number;
  match_note: string | null;
};
type ExhaustedOffer = {
  id: string;
  merchant_id: string;
  value: number;
  offer_type: string;
  budget_total_points: number | null;
  budget_spent_points: number;
};

export default async function AlertsPage() {
  const supabase = supabaseAdmin();

  const { data: ambiguous } = await supabase
    .from("card_transactions")
    .select("id, merchant_ruc, amount, card_last4, card_brand, occurred_at, match_note")
    .eq("match_status", "ambiguous")
    .order("occurred_at", { ascending: false })
    .returns<AmbiguousRow[]>();

  const { data: unmatchedBank } = await supabase
    .from("savings_bank_reports")
    .select("id, external_account_ref, period_month, avg_balance, match_note")
    .eq("match_status", "unmatched")
    .order("provided_at", { ascending: false })
    .returns<UnmatchedBankRow[]>();

  const { data: exhausted } = await supabase
    .from("partner_merchant_offers")
    .select("id, merchant_id, value, offer_type, budget_total_points, budget_spent_points")
    .eq("status", "budget_exhausted")
    .returns<ExhaustedOffer[]>();

  const merchantIds = [...new Set((exhausted ?? []).map((offer) => offer.merchant_id))];
  const { data: exhaustedMerchants } = merchantIds.length
    ? await supabase.from("partner_merchants").select("id, name").in("id", merchantIds).returns<{ id: string; name: string }[]>()
    : { data: [] as { id: string; name: string }[] };
  const merchantNameById = new Map((exhaustedMerchants ?? []).map((m) => [m.id, m.name]));

  return (
    <>
      <h1>Alertas</h1>

      <div className="card">
        <h3>Compras ambiguas (2+ tarjetas posibles — sin puntos)</h3>
        <table>
          <thead>
            <tr>
              <th>Fecha</th>
              <th>RUC</th>
              <th>Monto</th>
              <th>Tarjeta</th>
              <th>Nota</th>
            </tr>
          </thead>
          <tbody>
            {(ambiguous ?? []).map((row) => (
              <tr key={row.id}>
                <td>{new Date(row.occurred_at).toLocaleString("es-PA")}</td>
                <td>{row.merchant_ruc}</td>
                <td>${Number(row.amount).toFixed(2)}</td>
                <td>
                  {row.card_brand} •••• {row.card_last4}
                </td>
                <td className="text-dim">{row.match_note ?? "—"}</td>
              </tr>
            ))}
            {(ambiguous ?? []).length === 0 && (
              <tr>
                <td colSpan={5} className="text-dim">
                  Sin compras ambiguas.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h3>Reportes de banco sin inscripcion que los reclame</h3>
        <table>
          <thead>
            <tr>
              <th>Periodo</th>
              <th>Cuenta</th>
              <th>Saldo</th>
              <th>Nota</th>
            </tr>
          </thead>
          <tbody>
            {(unmatchedBank ?? []).map((row) => (
              <tr key={row.id}>
                <td>{row.period_month}</td>
                <td>{row.external_account_ref}</td>
                <td>${Number(row.avg_balance).toFixed(2)}</td>
                <td className="text-dim">{row.match_note ?? "—"}</td>
              </tr>
            ))}
            {(unmatchedBank ?? []).length === 0 && (
              <tr>
                <td colSpan={4} className="text-dim">
                  Sin reportes sin cruzar.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h3>Campañas con presupuesto agotado</h3>
        <table>
          <thead>
            <tr>
              <th>Comercio</th>
              <th>Oferta</th>
              <th>Consumido</th>
            </tr>
          </thead>
          <tbody>
            {(exhausted ?? []).map((offer) => (
              <tr key={offer.id}>
                <td>{merchantNameById.get(offer.merchant_id) ?? "—"}</td>
                <td>{offer.offer_type === "percent" ? `${offer.value} pts/$` : `${offer.value} pts fijos`}</td>
                <td>
                  {offer.budget_spent_points} / {offer.budget_total_points}
                </td>
              </tr>
            ))}
            {(exhausted ?? []).length === 0 && (
              <tr>
                <td colSpan={3} className="text-dim">
                  Ninguna campaña agotada.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </>
  );
}

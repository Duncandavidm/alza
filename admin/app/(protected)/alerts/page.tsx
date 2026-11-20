import { supabaseAdmin } from "@/lib/supabase-admin";
import { formatCashback } from "@/lib/format";

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
                <td>{offer.offer_type === "percent" ? `${offer.value} % de cashback` : `${formatCashback(offer.value)} fijos de cashback`}</td>
                <td>
                  {formatCashback(offer.budget_spent_points)} / {formatCashback(offer.budget_total_points)}
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

import { notFound } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { createOffer, updateOfferStatus } from "./actions";

type Merchant = { id: string; name: string; ruc: string; status: string };
type Offer = {
  id: string;
  offer_type: "percent" | "fixed";
  value: number;
  min_amount: number | null;
  starts_at: string;
  ends_at: string | null;
  budget_total_points: number | null;
  budget_spent_points: number;
  status: "active" | "paused" | "budget_exhausted";
};

export default async function MerchantDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = supabaseAdmin();

  const { data: merchant } = await supabase
    .from("partner_merchants")
    .select("id, name, ruc, status")
    .eq("id", id)
    .maybeSingle<Merchant>();
  if (!merchant) notFound();

  const { data: offers } = await supabase
    .from("partner_merchant_offers")
    .select("id, offer_type, value, min_amount, starts_at, ends_at, budget_total_points, budget_spent_points, status")
    .eq("merchant_id", id)
    .order("starts_at", { ascending: false })
    .returns<Offer[]>();

  return (
    <>
      <h1>{merchant.name}</h1>
      <p className="text-dim">
        RUC {merchant.ruc} — <span className={`badge ${merchant.status}`}>{merchant.status}</span>
      </p>

      <div className="card">
        <h3>Nueva oferta</h3>
        <form action={createOffer.bind(null, merchant.id)} className="grid-form">
          <div className="field">
            <label>Tipo</label>
            <select name="offer_type" defaultValue="percent">
              <option value="percent">% en puntos por dolar</option>
              <option value="fixed">Puntos fijos por compra</option>
            </select>
          </div>
          <div className="field">
            <label>Valor (puntos por dolar, o puntos fijos)</label>
            <input type="number" name="value" step="0.01" min="0.01" required />
          </div>
          <div className="field">
            <label>Compra minima (opcional)</label>
            <input type="number" name="min_amount" step="0.01" min="0" />
          </div>
          <div className="field">
            <label>Presupuesto total de puntos (opcional)</label>
            <input type="number" name="budget_total_points" step="1" min="1" />
          </div>
          <div className="field">
            <label>Termina el (opcional)</label>
            <input type="date" name="ends_at" />
          </div>
          <div className="field" style={{ alignSelf: "end" }}>
            <button type="submit">Crear oferta</button>
          </div>
        </form>
      </div>

      <div className="card">
        <h3>Ofertas</h3>
        <table>
          <thead>
            <tr>
              <th>Tipo</th>
              <th>Valor</th>
              <th>Minimo</th>
              <th>Presupuesto</th>
              <th>Termina</th>
              <th>Estado</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {(offers ?? []).map((offer) => (
              <tr key={offer.id}>
                <td>{offer.offer_type === "percent" ? "% por dolar" : "Fijo"}</td>
                <td>{offer.value}</td>
                <td>{offer.min_amount ?? "—"}</td>
                <td>
                  {offer.budget_total_points !== null
                    ? `${offer.budget_spent_points} / ${offer.budget_total_points} pts`
                    : "Sin tope"}
                </td>
                <td>{offer.ends_at ? new Date(offer.ends_at).toLocaleDateString("es-PA") : "—"}</td>
                <td>
                  <span className={`badge ${offer.status}`}>{offer.status}</span>
                </td>
                <td>
                  {offer.status !== "budget_exhausted" && (
                    <form action={updateOfferStatus.bind(null, merchant.id, offer.id, offer.status === "active" ? "paused" : "active")}>
                      <button type="submit" className="secondary">
                        {offer.status === "active" ? "Pausar" : "Reactivar"}
                      </button>
                    </form>
                  )}
                </td>
              </tr>
            ))}
            {(offers ?? []).length === 0 && (
              <tr>
                <td colSpan={7} className="text-dim">
                  Sin ofertas todavia.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </>
  );
}

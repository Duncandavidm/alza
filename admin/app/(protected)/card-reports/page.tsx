import { supabaseAdmin } from "@/lib/supabase-admin";
import { formatCashback } from "@/lib/format";
import UploadCardReportForm from "./UploadCardReportForm";
import RunReconciliationButton from "./RunReconciliationButton";

type Merchant = { id: string; name: string; ruc: string };
type CardTransactionRow = {
  id: string;
  provider_transaction_id: string;
  merchant_ruc: string;
  amount: number;
  card_last4: string;
  card_brand: string;
  occurred_at: string;
  match_status: string;
  match_note: string | null;
  points_awarded: number | null;
};

export default async function CardReportsPage() {
  const supabase = supabaseAdmin();

  const { data: merchants } = await supabase
    .from("partner_merchants")
    .select("id, name, ruc")
    .eq("status", "active")
    .order("name", { ascending: true })
    .returns<Merchant[]>();

  const { data: recent } = await supabase
    .from("card_transactions")
    .select("id, provider_transaction_id, merchant_ruc, amount, card_last4, card_brand, occurred_at, match_status, match_note, points_awarded")
    .eq("provider", "merchant_report")
    .order("ingested_at", { ascending: false })
    .limit(50)
    .returns<CardTransactionRow[]>();

  return (
    <>
      <h1>Reportes de tarjeta (comercios aliados)</h1>
      <p className="text-dim">
        Sube las ventas con tarjeta de un comercio aliado — se cruzan por ultimos 4 digitos + marca contra las
        tarjetas vinculadas por los usuarios. Si hay mas de una tarjeta posible, no se asigna cashback (queda
        "ambiguous", ver Alertas).
      </p>

      <div className="card">
        <h3>Subir reporte</h3>
        {(merchants ?? []).length === 0 ? (
          <p className="text-dim">Crea un comercio aliado activo primero.</p>
        ) : (
          <UploadCardReportForm merchants={merchants ?? []} />
        )}
        <p className="text-dim" style={{ marginTop: 10 }}>
          Columnas del CSV: <code>provider_transaction_id, occurred_at, amount, card_last4, card_brand</code> (y
          opcionalmente <code>branch</code>). <code>card_brand</code>: visa, mastercard, amex u other.
        </p>
      </div>

      <div className="card">
        <RunReconciliationButton />
      </div>

      <div className="card">
        <h3>Ultimos reportes</h3>
        <table>
          <thead>
            <tr>
              <th>Fecha</th>
              <th>RUC</th>
              <th>Monto</th>
              <th>Tarjeta</th>
              <th>Estado</th>
              <th>Nota</th>
              <th>Cashback</th>
            </tr>
          </thead>
          <tbody>
            {(recent ?? []).map((row) => (
              <tr key={row.id}>
                <td>{new Date(row.occurred_at).toLocaleString("es-PA")}</td>
                <td>{row.merchant_ruc}</td>
                <td>${Number(row.amount).toFixed(2)}</td>
                <td>
                  {row.card_brand} •••• {row.card_last4}
                </td>
                <td>
                  <span className={`badge ${row.match_status}`}>{row.match_status}</span>
                </td>
                <td className="text-dim">{row.match_note ?? "—"}</td>
                <td>{row.points_awarded !== null ? formatCashback(row.points_awarded) : "—"}</td>
              </tr>
            ))}
            {(recent ?? []).length === 0 && (
              <tr>
                <td colSpan={7} className="text-dim">
                  Sin reportes todavia.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </>
  );
}

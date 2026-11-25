import { supabaseAdmin } from "@/lib/supabase-admin";
import { formatInt, formatMoney } from "@/lib/format";

type Row = {
  month: string;
  merchant_id: string;
  merchant: string;
  delivered: number;
  amount_usd: number;
  outstanding: number;
  outstanding_usd: number;
};

/// Liquidacion de los bonos en US$ que paga MonAvi (desbloqueados con
/// cashback o gratis) y que el comercio ya aplico en caja, por comercio y
/// por mes (monavi_bono_settlement, migracion 0085).
export default async function BonoSettlement({ months = 6 }: { months?: number }) {
  const { data, error } = await supabaseAdmin().rpc("monavi_bono_settlement", { p_months: months });
  const rows = (data ?? []) as Row[];

  const totals = new Map<string, { merchant: string; delivered: number; amount: number; outstanding: number; outstandingUsd: number }>();
  for (const row of rows) {
    const total = totals.get(row.merchant_id) ?? {
      merchant: row.merchant,
      delivered: 0,
      amount: 0,
      outstanding: Number(row.outstanding),
      outstandingUsd: Number(row.outstanding_usd),
    };
    total.delivered += Number(row.delivered);
    total.amount += Number(row.amount_usd);
    totals.set(row.merchant_id, total);
  }
  const byMerchant = [...totals.values()].sort((a, b) => b.amount - a.amount);
  const grandTotal = byMerchant.reduce((sum, row) => sum + row.amount, 0);

  return (
    <div className="card table-scroll">
      <h3>Bonos que paga MonAvi (últimos {months} meses)</h3>
      <p className="text-dim">
        Bonos en US$ marcados como «los paga MonAvi» que ya se aplicaron en caja (desbloqueados con cashback o gratis). Es
        lo que le pagas a cada comercio. &quot;Por usar&quot; son bonos desbloqueados que el cliente todavía puede usar.
      </p>
      {error && <p className="error">No se pudo calcular la liquidación de bonos: {error.message}</p>}
      <table>
        <thead>
          <tr>
            <th>Comercio</th>
            <th>Usados</th>
            <th>A pagar</th>
            <th>Por usar</th>
          </tr>
        </thead>
        <tbody>
          {byMerchant.map((row) => (
            <tr key={row.merchant}>
              <td>{row.merchant}</td>
              <td>{formatInt(row.delivered)}</td>
              <td><strong>{formatMoney(row.amount)}</strong></td>
              <td className="text-dim">
                {formatInt(row.outstanding)}
                {row.outstanding > 0 ? ` (${formatMoney(row.outstandingUsd)})` : ""}
              </td>
            </tr>
          ))}
          {byMerchant.length > 0 && (
            <tr>
              <td><strong>Total</strong></td>
              <td></td>
              <td><strong>{formatMoney(grandTotal)}</strong></td>
              <td></td>
            </tr>
          )}
          {byMerchant.length === 0 && (
            <tr>
              <td colSpan={4} className="text-dim">Todavía no se ha usado ningún bono pagado por MonAvi.</td>
            </tr>
          )}
        </tbody>
      </table>
      {rows.length > 0 && (
        <>
          <h4 style={{ margin: "16px 0 6px" }}>Detalle por mes</h4>
          <table>
            <thead>
              <tr>
                <th>Mes</th>
                <th>Comercio</th>
                <th>Usados</th>
                <th>A pagar</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={`${row.month}-${row.merchant_id}`}>
                  <td>{row.month}</td>
                  <td>{row.merchant}</td>
                  <td>{formatInt(row.delivered)}</td>
                  <td>{formatMoney(row.amount_usd)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
    </div>
  );
}

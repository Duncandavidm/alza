import { supabaseAdmin } from "@/lib/supabase-admin";
import { formatInt, formatMoney } from "@/lib/format";

type Row = {
  month: string;
  merchant_id: string;
  merchant: string;
  delivered_habits: number;
  delivered_gifts: number;
  delivered: number;
  amount_usd: number;
  outstanding: number;
  outstanding_usd: number;
};

/// Liquidacion a comercios: todos los cupones que paga MonAvi (automaticos
/// por buenos habitos + regalados), usados en caja, por mes y comercio,
/// con el total por comercio arriba (coupon_settlement, migracion 0075).
export default async function CouponSettlement({ months = 6 }: { months?: number }) {
  const { data, error } = await supabaseAdmin().rpc("coupon_settlement", { p_months: months });
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
      <h3>Liquidación a comercios (últimos {months} meses)</h3>
      <p className="text-dim">
        Todos los cupones que paga MonAvi y que ya se usaron en caja: los automáticos por buenos hábitos y los que
        regalaste. Es lo que le pagas a cada comercio. &quot;Por usar&quot; son cupones entregados que el cliente todavía puede
        usar (lo que podrías pagar después).
      </p>
      {error && <p className="error">No se pudo calcular la liquidación: {error.message}</p>}

      <h4 style={{ marginBottom: 6 }}>Total por comercio</h4>
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
              <td colSpan={4} className="text-dim">Todavía no se ha usado ningún cupón en caja.</td>
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
                <th>Por hábitos</th>
                <th>Regalados</th>
                <th>A pagar</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={`${row.month}-${row.merchant_id}`}>
                  <td>{row.month}</td>
                  <td>{row.merchant}</td>
                  <td>{formatInt(row.delivered_habits)}</td>
                  <td>{formatInt(row.delivered_gifts)}</td>
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

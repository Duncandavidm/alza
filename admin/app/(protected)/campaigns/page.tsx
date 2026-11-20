import Link from "next/link";
import { supabaseAdmin } from "@/lib/supabase-admin";
import ActionForm from "@/components/ActionForm";
import CampaignFieldsInputs from "@/components/CampaignFieldsInputs";
import { CAMPAIGN_COLUMNS, CAMPAIGN_STATUS_LABELS, type Campaign, toCampaignStatus, toPanamaDateInput } from "@/lib/campaigns";
import { formatRewardValue, toRewardCurrency } from "@/lib/currency";
import { formatDate, formatInt } from "@/lib/format";
import { createCampaign } from "./actions";

export default async function CampaignsPage() {
  const supabase = supabaseAdmin();
  const { data: campaigns, error } = await supabase
    .from("brand_campaigns")
    .select(CAMPAIGN_COLUMNS)
    .order("created_at", { ascending: false })
    .returns<Campaign[]>();

  // Ventas verificadas por campaña (conteo exacto, sin traer las filas).
  const conversionCounts = new Map<string, number>(
    await Promise.all(
      (campaigns ?? []).map(async (campaign) => {
        const { count } = await supabase
          .from("campaign_conversions")
          .select("id", { count: "exact", head: true })
          .eq("campaign_id", campaign.id);
        return [campaign.id, count ?? 0] as [string, number];
      })
    )
  );

  return (
    <>
      <h1>Campañas de marcas</h1>
      <p className="text-dim">
        Una marca paga para que los clientes de MonAvi ganen un premio extra cuando compran su producto. La campaña se
        verifica sola con las facturas DGI: si una línea de la factura contiene alguna de sus palabras, el cliente recibe
        el premio y se cuenta una venta verificada, que es lo que se le cobra a la marca.
      </p>

      {error && (
        <div className="card">
          <p className="error">No se pudieron leer las campañas: {error.message}</p>
        </div>
      )}

      <div className="card table-scroll">
        <table>
          <thead>
            <tr>
              <th>Marca</th>
              <th>Campaña</th>
              <th>Estado</th>
              <th>Fechas</th>
              <th>Presupuesto usado</th>
              <th>Ventas verificadas</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {(campaigns ?? []).map((campaign) => {
              const status = toCampaignStatus(campaign.status);
              const currency = toRewardCurrency(campaign.bonus_currency);
              return (
                <tr key={campaign.id}>
                  <td>{campaign.brand}</td>
                  <td>
                    <Link href={`/campaigns/${campaign.id}`}>{campaign.name}</Link>
                    {campaign.description && <div className="text-dim">{campaign.description}</div>}
                  </td>
                  <td>
                    <span className={`badge ${status}`}>{CAMPAIGN_STATUS_LABELS[status]}</span>
                  </td>
                  <td className="text-dim">
                    {formatDate(campaign.starts_at)} → {campaign.ends_at ? formatDate(campaign.ends_at) : "sin fin"}
                  </td>
                  <td>
                    {formatRewardValue(campaign.budget_spent, currency)}
                    <span className="text-dim">
                      {" "}
                      / {campaign.budget_total ? formatRewardValue(campaign.budget_total, currency) : "sin tope"}
                    </span>
                  </td>
                  <td>{formatInt(conversionCounts.get(campaign.id) ?? 0)}</td>
                  <td>
                    <Link href={`/campaigns/${campaign.id}`}>Ficha y reporte</Link>
                  </td>
                </tr>
              );
            })}
            {(campaigns ?? []).length === 0 && (
              <tr>
                <td colSpan={7} className="text-dim">
                  Todavía no hay campañas de marcas.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h3>Nueva campaña</h3>
        <p className="text-dim">
          Se crea en <strong>borrador</strong>: no premia ninguna factura hasta que la actives desde su ficha.
        </p>
        <ActionForm action={createCampaign} className="grid-form" submitLabel="Crear campaña" pendingLabel="Creando…">
          <CampaignFieldsInputs today={toPanamaDateInput(new Date().toISOString())} />
        </ActionForm>
      </div>
    </>
  );
}

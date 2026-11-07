import Link from "next/link";
import { notFound } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase-admin";
import ActionForm from "@/components/ActionForm";
import CampaignFieldsInputs from "@/components/CampaignFieldsInputs";
import { BarList, Kpi } from "@/components/Charts";
import {
  CAMPAIGN_COLUMNS,
  CAMPAIGN_STATUS_LABELS,
  type Campaign,
  type CampaignStatus,
  bonusValueToInput,
  endsAtToDateInput,
  normalizeCampaignReport,
  toCampaignStatus,
  toPanamaDateInput,
} from "@/lib/campaigns";
import { REWARD_CURRENCY_LABELS, formatRewardValue, formatRewardValueLong, toRewardCurrency } from "@/lib/currency";
import { centsToDollarInput, formatCashback, formatDate, formatDateTime, formatInt, formatMoney, num } from "@/lib/format";
import { setCampaignStatus, updateCampaign } from "../actions";

export default async function CampaignDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = supabaseAdmin();

  const { data: campaign } = await supabase
    .from("brand_campaigns")
    .select(CAMPAIGN_COLUMNS)
    .eq("id", id)
    .maybeSingle<Campaign>();
  if (!campaign) notFound();

  const { data: rawReport, error: reportError } = await supabase.rpc("brand_campaign_report", { p_campaign_id: id });
  const report = normalizeCampaignReport(rawReport);

  const status = toCampaignStatus(campaign.status);
  const currency = toRewardCurrency(campaign.bonus_currency);
  const percent = campaign.bonus_percent === null ? null : num(campaign.bonus_percent);

  const prizeParts: string[] = [];
  if (campaign.bonus_per_unit) prizeParts.push(`${formatRewardValueLong(campaign.bonus_per_unit, currency)} por unidad`);
  if (percent) {
    prizeParts.push(
      `${percent.toLocaleString("es-PA", { maximumFractionDigits: 2 })} ${currency === "puntos" ? "puntos" : "centavos"} extra por dólar`
    );
  }

  const statusActions: { status: CampaignStatus; label: string; className?: string }[] = [];
  if (status !== "active") {
    statusActions.push({ status: "active", label: status === "draft" ? "Activar campaña" : "Reactivar" });
  }
  if (status === "active") statusActions.push({ status: "paused", label: "Pausar", className: "secondary" });
  if (status !== "ended") statusActions.push({ status: "ended", label: "Terminar", className: "danger" });

  return (
    <>
      <p className="text-dim">
        <Link href="/campaigns">← Campañas de marcas</Link>
      </p>
      <h1 style={{ marginBottom: 4 }}>{campaign.name}</h1>
      <p className="text-dim" style={{ marginTop: 0 }}>
        {campaign.brand} · <span className={`badge ${status}`}>{CAMPAIGN_STATUS_LABELS[status]}</span>{" "}
        <span className={`badge currency-${currency}`}>{REWARD_CURRENCY_LABELS[currency]}</span> ·{" "}
        {formatDate(campaign.starts_at)} → {campaign.ends_at ? formatDate(campaign.ends_at) : "sin fin"}
      </p>

      <div className="card">
        <h3>Estado</h3>
        <p className="text-dim">
          {campaign.description ? `“${campaign.description}”. ` : ""}
          Premio: {prizeParts.join(" + ") || "—"}, hasta {formatInt(campaign.max_units_per_receipt)} unidades por factura.
          Palabras: {campaign.keywords.join(", ")}.{" "}
          {campaign.merchant_rucs?.length ? `Solo en RUC ${campaign.merchant_rucs.join(", ")}.` : "En todos los comercios."}{" "}
          Presupuesto: {formatRewardValue(campaign.budget_spent, currency)} usado de{" "}
          {campaign.budget_total ? formatRewardValue(campaign.budget_total, currency) : "sin tope"}.
        </p>
        {status === "budget_exhausted" && (
          <p className="error">
            Se agotó el presupuesto de premios: sube el presupuesto en la ficha antes de reactivarla.
          </p>
        )}
        {status === "draft" && (
          <p className="text-dim">En borrador no premia ninguna factura. Revisa los datos y actívala cuando la marca confirme.</p>
        )}
        <div className="inline-actions">
          {statusActions.map((action) => (
            <form key={action.status} action={setCampaignStatus.bind(null, campaign.id, action.status)}>
              <button type="submit" className={action.className}>
                {action.label}
              </button>
            </form>
          ))}
        </div>
        <p className="text-dim" style={{ marginBottom: 0 }}>
          Actualizada {formatDateTime(campaign.updated_at)}
          {campaign.sponsor_contact ? ` · Contacto: ${campaign.sponsor_contact}` : ""}
        </p>
      </div>

      <section className="card insights-section">
        <h3>Resultados</h3>
        <p className="text-dim insights-caption">
          Cada venta verificada es una factura DGI confirmada que incluyó el producto de la marca. Es la base de lo que se le
          cobra a la marca ({campaign.fee_per_conversion_cents !== null ? formatCashback(campaign.fee_per_conversion_cents) : "sin tarifa"}{" "}
          por venta).
        </p>
        {reportError ? (
          <p className="error">No se pudo generar el reporte: {reportError.message}</p>
        ) : (
          <div className="kpi-grid">
            <Kpi label="Ventas verificadas" value={formatInt(report.conversions)} />
            <Kpi label="Unidades" value={formatInt(report.units)} />
            <Kpi label="Personas" value={formatInt(report.people)} />
            <Kpi label="Monto en facturas" value={formatMoney(report.sales)} hint="Total de las líneas con el producto" />
            <Kpi label="Premios entregados" value={formatRewardValue(num(report.bonus_given), currency)} />
            <Kpi label="Monto a cobrar a la marca" value={formatCashback(report.amount_due_cents)} />
          </div>
        )}
      </section>

      <div className="insights-two">
        <section className="card insights-section">
          <h3>Por semana</h3>
          <p className="text-dim insights-caption">Ventas verificadas por semana (lunes a domingo, hora de Panamá).</p>
          <BarList
            emptyText="Todavía no hay ventas verificadas."
            items={report.by_week.map((row) => ({
              label: `Semana del ${weekLabel(row.week)}`,
              value: num(row.conversions),
              detail: `${formatInt(row.conversions)} ventas · ${formatInt(row.units)} unidades · ${formatMoney(row.sales)}`,
            }))}
          />
        </section>

        <section className="card insights-section">
          <h3>Por comercio</h3>
          <p className="text-dim insights-caption">
            Dónde se compró el producto. Solo se muestran comercios con al menos 5 personas, para proteger su privacidad.
          </p>
          {report.by_merchant.length > 0 ? (
            <div className="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th>Comercio</th>
                    <th>Ventas</th>
                    <th>Personas</th>
                    <th>Unidades</th>
                    <th>Monto</th>
                  </tr>
                </thead>
                <tbody>
                  {report.by_merchant.map((row, index) => (
                    <tr key={`${row.merchant}-${index}`}>
                      <td>{row.merchant ?? "—"}</td>
                      <td>{formatInt(row.conversions)}</td>
                      <td>{formatInt(row.people)}</td>
                      <td>{formatInt(row.units)}</td>
                      <td>{formatMoney(row.sales)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <p className="text-dim">Sin datos suficientes (ningún comercio llega a 5 personas).</p>
          )}
        </section>
      </div>

      <div className="card">
        <h3>Ficha de la campaña</h3>
        <p className="text-dim">
          La descripción es lo que ve el cliente en la app. Los cambios aplican a las facturas que se confirmen desde ahora.
        </p>
        <ActionForm action={updateCampaign.bind(null, campaign.id)} className="grid-form" submitLabel="Guardar campaña">
          <CampaignFieldsInputs
            today={toPanamaDateInput(new Date().toISOString())}
            defaults={{
              brand: campaign.brand,
              name: campaign.name,
              description: campaign.description,
              image_url: campaign.image_url,
              sponsor_contact: campaign.sponsor_contact,
              keywords: campaign.keywords,
              merchant_rucs: campaign.merchant_rucs,
              bonus_currency: currency,
              bonus_per_unit: bonusValueToInput(campaign.bonus_per_unit, currency),
              bonus_percent: percent === null ? "" : String(percent),
              max_units_per_receipt: campaign.max_units_per_receipt,
              fee_per_conversion:
                campaign.fee_per_conversion_cents === null ? "" : centsToDollarInput(campaign.fee_per_conversion_cents),
              budget_total: bonusValueToInput(campaign.budget_total, currency),
              starts_at: toPanamaDateInput(campaign.starts_at),
              ends_at: endsAtToDateInput(campaign.ends_at),
            }}
          />
        </ActionForm>
      </div>
    </>
  );
}

function weekLabel(week: string | null): string {
  if (!week) return "—";
  const date = new Date(`${week}T12:00:00Z`);
  if (Number.isNaN(date.getTime())) return week;
  return date.toLocaleDateString("es-PA", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });
}

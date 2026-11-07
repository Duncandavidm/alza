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

export default async function CampaignDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ try?: string | string[] }>;
}) {
  const { id } = await params;
  const query = await searchParams;
  const tryRaw = (Array.isArray(query.try) ? query.try[0] : query.try) ?? "";
  const supabase = supabaseAdmin();

  const { data: campaign } = await supabase
    .from("brand_campaigns")
    .select(CAMPAIGN_COLUMNS)
    .eq("id", id)
    .maybeSingle<Campaign>();
  if (!campaign) notFound();

  const { data: rawReport, error: reportError } = await supabase.rpc("brand_campaign_report", { p_campaign_id: id });
  const report = normalizeCampaignReport(rawReport);

  // "Probar palabras": que lineas reales de facturas encontrarian las
  // palabras de la campaña (o las que se escriban en el cuadro).
  const triedWords = parseKeywordList(tryRaw);
  const testWords = triedWords.length > 0 ? triedWords : campaign.keywords;
  const { data: rawMatches, error: matchesError } =
    testWords.length > 0
      ? await supabase.rpc("campaign_keyword_matches", { p_keywords: testWords, p_days: 90 })
      : { data: [], error: null };
  const matches = (Array.isArray(rawMatches) ? rawMatches : []) as KeywordMatch[];

  const pushHref = `/notificaciones?${new URLSearchParams({
    title: `Gana más con ${campaign.brand}`.slice(0, 80),
    body: (campaign.description || `Compra ${campaign.brand}, escanea tu factura y gana un premio extra en MonAvi.`).slice(0, 240),
    screen: "points",
    brand_campaign_id: campaign.id,
    ...(campaign.keywords[0] ? { product: campaign.keywords[0] } : {}),
  }).toString()}`;

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
          <Link href={pushHref} className="button secondary-link">
            Avisar por push
          </Link>
        </div>
        <p className="text-dim" style={{ marginBottom: 0 }}>
          “Avisar por push” abre Notificaciones con el mensaje listo y, como sugerencia, a quienes ya compraron “
          {campaign.keywords[0] ?? "el producto"}” (puedes quitar ese filtro).
        </p>
        <p className="text-dim" style={{ marginBottom: 0 }}>
          Actualizada {formatDateTime(campaign.updated_at)}
          {campaign.sponsor_contact ? ` · Contacto: ${campaign.sponsor_contact}` : ""}
        </p>
      </div>

      <section className="card" id="probar">
        <h3>Probar palabras</h3>
        <p className="text-dim insights-caption">
          Líneas reales de facturas de los últimos 90 días que estas palabras premiarían. La búsqueda ignora tildes y
          mayúsculas y busca la palabra <em>dentro</em> del texto de la línea. Cada comercio abrevia distinto: agrega
          variantes como “coca cola, cocacola, coca-cola”.
        </p>
        <form method="get" action={`/campaigns/${campaign.id}#probar`} className="inline-actions" style={{ marginBottom: 12 }}>
          <input
            type="text"
            name="try"
            defaultValue={triedWords.join(", ")}
            placeholder={campaign.keywords.join(", ")}
            style={{ flex: "1 1 280px" }}
            aria-label="Palabras a probar, separadas por coma"
          />
          <button type="submit">Probar</button>
          {triedWords.length > 0 && (
            <Link href={`/campaigns/${campaign.id}#probar`} className="button secondary-link">
              Volver a las de la campaña
            </Link>
          )}
        </form>
        <p className="text-dim">
          Probando: {testWords.length > 0 ? testWords.map((word) => `“${word}”`).join(", ") : "—"}
          {triedWords.length > 0 ? " (no se guardan: cópialas a la ficha si te sirven)" : " (palabras de la campaña)"}
        </p>
        {matchesError ? (
          <p className="error">No se pudo probar: {matchesError.message}</p>
        ) : matches.length === 0 ? (
          <p className="text-dim">Ninguna línea de factura coincide. Prueba variantes más cortas o abreviadas.</p>
        ) : (
          <div className="table-scroll" style={{ maxHeight: 360, overflowY: "auto" }}>
            <table>
              <thead>
                <tr>
                  <th>Texto en la factura</th>
                  <th>Veces</th>
                  <th>Unidades</th>
                </tr>
              </thead>
              <tbody>
                {matches.map((row, index) => (
                  <tr key={`${row.description}-${index}`}>
                    <td>
                      <code>{row.description ?? "—"}</code>
                    </td>
                    <td>{formatInt(row.times)}</td>
                    <td>{formatDecimalUnits(row.units)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

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

type KeywordMatch = { description: string | null; times: number | string | null; units: number | string | null };

/// "coca cola, cocacola" -> ["coca cola", "cocacola"] (max 20 palabras).
function parseKeywordList(raw: string): string[] {
  const words = raw
    .split(/[,\n;]/)
    .map((word) => word.replace(/\s+/g, " ").trim().slice(0, 60))
    .filter(Boolean);
  return [...new Set(words)].slice(0, 20);
}

function formatDecimalUnits(value: unknown): string {
  const parsed = num(value);
  return Number.isInteger(parsed) ? formatInt(parsed) : parsed.toLocaleString("es-PA", { maximumFractionDigits: 2 });
}

function weekLabel(week: string | null): string {
  if (!week) return "—";
  const date = new Date(`${week}T12:00:00Z`);
  if (Number.isNaN(date.getTime())) return week;
  return date.toLocaleDateString("es-PA", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });
}

import Link from "next/link";
import { supabaseAdmin } from "@/lib/supabase-admin";
import ActionForm from "@/components/ActionForm";
import PushComposer, { PushPreview } from "@/components/PushComposer";
import SegmentFields from "@/components/SegmentFields";
import SegmentReach, { ConsentNote } from "@/components/SegmentReach";
import { fetchSegmentMerchants, fetchSegmentPreview } from "@/lib/segment-preview";
import { parseSegment, segmentFromJson, segmentSummary, segmentToFields } from "@/lib/segments";
import {
  PUSH_BODY_MAX,
  PUSH_SCREEN_LABELS,
  PUSH_STATUS_LABELS,
  PUSH_TITLE_MAX,
  cleanLine,
  parseUuid,
  toPushScreen,
} from "@/lib/push";
import { skippedNote } from "@/lib/edge";
import { formatDateTime, formatInt } from "@/lib/format";
import { retryPushCampaign, sendPushCampaign } from "./actions";

export const dynamic = "force-dynamic";

type SearchParams = Record<string, string | string[] | undefined>;

type PushRow = {
  id: string;
  title: string;
  body: string;
  screen: string;
  segment: unknown;
  brand_campaign_id: string | null;
  status: string;
  target_count: number;
  sent_count: number;
  failed_count: number;
  error: string | null;
  created_at: string;
  sent_at: string | null;
  brand_campaigns: { name: string } | { name: string }[] | null;
};

function first(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

// Notificaciones push segmentadas. Todo el formulario va por GET:
// "Calcular alcance" recarga con los datos en la URL, la pagina muestra el
// alcance y un recuadro de confirmacion con exactamente lo que se enviara.
// Otras paginas enlazan aqui con ?title=&body=&screen=&brand_campaign_id=&product=.
export default async function NotificacionesPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const params = await searchParams;
  const get = (key: string) => first(params[key]);

  const title = cleanLine(get("title"), PUSH_TITLE_MAX);
  const body = cleanLine(get("body"), PUSH_BODY_MAX);
  const screen = toPushScreen(get("screen"));
  const brandCampaignId = parseUuid(get("brand_campaign_id"));
  const segment = parseSegment(get);
  const review = get("review") === "1" || Boolean(get("preset"));
  const doneMessage = get("done") ? cleanLine(get("msg"), 600) : null;

  const supabase = supabaseAdmin();
  const [merchants, { data: history, error: historyError }, brand, reach] = await Promise.all([
    fetchSegmentMerchants(),
    supabase
      .from("push_campaigns")
      .select(
        "id, title, body, screen, segment, brand_campaign_id, status, target_count, sent_count, failed_count, error, created_at, sent_at, brand_campaigns(name)"
      )
      .order("created_at", { ascending: false })
      .limit(50)
      .returns<PushRow[]>(),
    brandCampaignId
      ? supabase.from("brand_campaigns").select("id, name, brand").eq("id", brandCampaignId).maybeSingle<{ id: string; name: string; brand: string }>()
      : Promise.resolve({ data: null }),
    review ? fetchSegmentPreview(segment) : Promise.resolve(null),
  ]);
  const brandCampaign = brand.data;

  const missing: string[] = [];
  if (!title) missing.push("el título");
  if (!body) missing.push("el mensaje");
  const people = reach?.preview?.people ?? 0;
  const withPush = reach?.preview?.with_push ?? 0;

  const hiddenFields: Record<string, string> = { title, body, screen, ...segmentToFields(segment) };
  if (brandCampaignId) hiddenFields.brand_campaign_id = brandCampaignId;

  return (
    <>
      <h1>Notificaciones</h1>
      <p className="text-dim">
        Envía un aviso push a un grupo de clientes de la app. Escribe el mensaje, elige a quién, calcula el alcance y
        confirma.
      </p>

      {doneMessage && (
        <div className="card" style={{ borderColor: "var(--success)" }}>
          <strong className="success-text">Listo.</strong> {doneMessage}
        </div>
      )}

      <form method="get" action="/notificaciones" className="card">
        <h3>Mensaje</h3>
        {brandCampaign && (
          <p className="text-dim">
            Vinculada a la campaña <Link href={`/campaigns/${brandCampaign.id}`}>{brandCampaign.name}</Link> (
            {brandCampaign.brand}).
          </p>
        )}
        {brandCampaignId && <input type="hidden" name="brand_campaign_id" value={brandCampaignId} />}
        <PushComposer defaultTitle={title} defaultBody={body} defaultScreen={screen} />

        <SegmentFields segment={segment} merchants={merchants} showPresets />

        <div className="inline-actions">
          <button type="submit" name="review" value="1">
            Calcular alcance
          </button>
          <a className="button secondary-link" href="/notificaciones">
            Empezar de nuevo
          </a>
        </div>
      </form>

      {reach && (
        <div className="card confirm-card" id="confirmar">
          <h3>Alcance y confirmación</h3>
          <p className="text-dim" style={{ marginTop: 0 }}>
            Para: {segmentSummary(segment)}
          </p>
          <SegmentReach preview={reach.preview} error={reach.error} />
          {reach.preview && (
            <div style={{ marginTop: 16 }}>
              {missing.length > 0 ? (
                <p className="error">Falta {missing.join(" y ")} para poder enviar.</p>
              ) : people === 0 ? (
                <p className="error">Nadie cumple estos filtros: ajústalos antes de enviar.</p>
              ) : (
                <div className="confirm-layout">
                  <PushPreview title={title} body={body} />
                  <div>
                    <p>
                      Se enviará a <strong>{formatInt(people)}</strong> personas; les llegará a las{" "}
                      <strong>{formatInt(withPush)}</strong> que tienen las notificaciones activadas. Al tocarla abre{" "}
                      <strong>{PUSH_SCREEN_LABELS[screen]}</strong>.
                    </p>
                    {withPush === 0 && (
                      <p className="text-dim">Nadie del grupo tiene notificaciones activas: se guardará pero no llegará a nadie.</p>
                    )}
                    <ActionForm
                      action={sendPushCampaign}
                      confirm={`¿Enviar ahora a ${formatInt(people)} personas? No se puede deshacer.`}
                      submitLabel="Guardar y enviar"
                      pendingLabel="Enviando…"
                    >
                      {Object.entries(hiddenFields).map(([name, value]) => (
                        <input key={name} type="hidden" name={name} value={value} />
                      ))}
                    </ActionForm>
                    <p className="text-dim">Si cambias el mensaje o los filtros, vuelve a “Calcular alcance” antes de enviar.</p>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      )}
      {!reach && (
        <div className="card">
          <ConsentNote />
        </div>
      )}

      <div className="card">
        <h3>Historial</h3>
        {historyError ? (
          <p className="error">No se pudo leer el historial: {historyError.message}</p>
        ) : (history ?? []).length === 0 ? (
          <p className="text-dim">Todavía no se ha enviado ninguna notificación.</p>
        ) : (
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>Fecha</th>
                  <th>Notificación</th>
                  <th>Para</th>
                  <th>Estado</th>
                  <th>Segmento</th>
                  <th>Recibieron</th>
                  <th>Fallidos</th>
                </tr>
              </thead>
              <tbody>
                {(history ?? []).map((row) => {
                  const brandName = Array.isArray(row.brand_campaigns)
                    ? row.brand_campaigns[0]?.name
                    : row.brand_campaigns?.name;
                  const note = row.status === "sent" ? skippedNote(row.error) : row.error;
                  return (
                    <tr key={row.id}>
                      <td>{formatDateTime(row.sent_at ?? row.created_at)}</td>
                      <td>
                        <strong>{row.title}</strong>
                        <div className="text-dim">{row.body}</div>
                        <div className="text-dim">
                          Abre: {PUSH_SCREEN_LABELS[toPushScreen(row.screen)]}
                          {brandName && row.brand_campaign_id && (
                            <>
                              {" "}
                              · Campaña <Link href={`/campaigns/${row.brand_campaign_id}`}>{brandName}</Link>
                            </>
                          )}
                        </div>
                      </td>
                      <td className="text-dim">{segmentSummary(segmentFromJson(row.segment))}</td>
                      <td>
                        <span className={`badge push-${row.status}`}>{PUSH_STATUS_LABELS[row.status] ?? row.status}</span>
                        {note && <div className="text-dim" style={{ marginTop: 4 }}>{note}</div>}
                        {(row.status === "draft" || row.status === "failed") && (
                          <form action={retryPushCampaign.bind(null, row.id)} style={{ marginTop: 6 }}>
                            <button type="submit" className="secondary">
                              Reintentar envío
                            </button>
                          </form>
                        )}
                      </td>
                      <td>{formatInt(row.target_count)}</td>
                      <td>{formatInt(row.sent_count)}</td>
                      <td>{formatInt(row.failed_count)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </>
  );
}

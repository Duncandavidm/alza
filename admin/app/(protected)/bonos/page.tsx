import { supabaseAdmin } from "@/lib/supabase-admin";
import ActionForm from "@/components/ActionForm";
import BonusFields from "@/components/BonusFields";
import SegmentFields from "@/components/SegmentFields";
import SegmentReach, { ConsentNote } from "@/components/SegmentReach";
import { fetchSegmentMerchants, fetchSegmentPreview } from "@/lib/segment-preview";
import { parseSegment, segmentFromJson, segmentSummary, segmentToFields } from "@/lib/segments";
import { BONUS_KIND_LABELS, bonusToFields, parseBonusInput, toBonusKind, type RewardOptionGroup } from "@/lib/bonuses";
import { cleanLine } from "@/lib/push";
import { formatRewardValue, toRewardCurrency } from "@/lib/currency";
import { embedded, formatCashback, formatDateTime, formatInt } from "@/lib/format";
import { grantBonus, retryBonus } from "./actions";

export const dynamic = "force-dynamic";

type SearchParams = Record<string, string | string[] | undefined>;

type MerchantRef = { name: string; status: string | null; reward_currency: string | null };

type RewardItemRow = {
  id: string;
  name: string;
  points_cost: number;
  status: string;
  partner_merchants: MerchantRef | MerchantRef[] | null;
};

type BonusRow = {
  id: string;
  name: string;
  kind: string;
  amount: number | null;
  reward_item_id: string | null;
  message: string | null;
  expires_days: number;
  segment: unknown;
  notify: boolean;
  status: string;
  granted_count: number;
  created_at: string;
  granted_at: string | null;
  reward_items: { name: string; partner_merchants: { name: string } | { name: string }[] | null } | null;
};

function first(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function bonusValue(row: BonusRow): string {
  const kind = toBonusKind(row.kind);
  if (kind === "cashback") return `${formatCashback(row.amount)} de cashback`;
  if (kind === "puntos") return `${formatInt(row.amount)} puntos`;
  const item = embedded(row.reward_items);
  const merchant = embedded(item?.partner_merchants ?? null);
  return `${item?.name ?? "Producto"}${merchant ? ` en ${merchant.name}` : ""} (vence en ${row.expires_days} días)`;
}

// Bonos y regalos: cashback, puntos o un producto gratis de un comercio
// aliado para un segmento. Mismo flujo que Notificaciones: formulario por
// GET -> "Calcular alcance" -> recuadro de confirmacion -> "Entregar".
export default async function BonosPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const params = await searchParams;
  const get = (key: string) => first(params[key]);

  const review = get("review") === "1" || Boolean(get("preset"));
  const parsed = parseBonusInput(get);
  const segment = parseSegment(get);
  const doneMessage = get("done") ? cleanLine(get("msg"), 600) : null;

  const supabase = supabaseAdmin();
  const [merchants, { data: items }, { data: history, error: historyError }, reach] = await Promise.all([
    fetchSegmentMerchants(),
    supabase
      .from("reward_items")
      .select("id, name, points_cost, status, partner_merchants(name, status, reward_currency)")
      .eq("status", "active")
      .order("name")
      .returns<RewardItemRow[]>(),
    supabase
      .from("bonus_grants")
      .select(
        "id, name, kind, amount, reward_item_id, message, expires_days, segment, notify, status, granted_count, created_at, granted_at, reward_items(name, partner_merchants(name))"
      )
      .order("created_at", { ascending: false })
      .limit(50)
      .returns<BonusRow[]>(),
    review ? fetchSegmentPreview(segment) : Promise.resolve(null),
  ]);

  // Productos activos agrupados por comercio (solo comercios activos).
  const groups = new Map<string, RewardOptionGroup>();
  for (const item of items ?? []) {
    const merchant = embedded(item.partner_merchants);
    if (!merchant || (merchant.status && merchant.status !== "active")) continue;
    const group = groups.get(merchant.name) ?? { merchant: merchant.name, items: [] };
    group.items.push({
      id: item.id,
      name: item.name,
      value: formatRewardValue(item.points_cost, toRewardCurrency(merchant.reward_currency)),
    });
    groups.set(merchant.name, group);
  }
  const rewardGroups = [...groups.values()].sort((a, b) => a.merchant.localeCompare(b.merchant, "es"));
  const itemLabel = new Map(rewardGroups.flatMap((g) => g.items.map((i) => [i.id, `${i.name} en ${g.merchant}`] as const)));

  // Regalos de producto ya usados en caja (reward_redemptions.status = 'entregado').
  const couponIds = (history ?? []).filter((row) => row.kind === "cupon").map((row) => row.id);
  const redeemedByBonus = new Map<string, number>();
  if (couponIds.length > 0) {
    const { data: redeemed } = await supabase
      .from("reward_redemptions")
      .select("bonus_id")
      .in("bonus_id", couponIds)
      .eq("status", "entregado")
      .limit(50000)
      .returns<{ bonus_id: string }[]>();
    for (const row of redeemed ?? []) redeemedByBonus.set(row.bonus_id, (redeemedByBonus.get(row.bonus_id) ?? 0) + 1);
  }

  const people = reach?.preview?.people ?? 0;
  const input = parsed.input;
  const what = input
    ? input.kind === "cashback"
      ? `${formatCashback(input.amount)} de cashback`
      : input.kind === "puntos"
        ? `${formatInt(input.amount)} puntos`
        : `${itemLabel.get(input.reward_item_id ?? "") ?? "un producto"} gratis (vence en ${input.expires_days} días)`
    : "";

  return (
    <>
      <h1>Bonos y regalos</h1>
      <p className="text-dim">
        Regala cashback, puntos o un producto gratis de un comercio aliado a un grupo de clientes. Cada persona lo recibe
        una sola vez por bono; los productos llegan como un código listo para canjear en caja (“🎁 Regalo de MonAvi”).
      </p>

      {doneMessage && (
        <div className="card" style={{ borderColor: "var(--success)" }}>
          <strong className="success-text">Listo.</strong> {doneMessage}
        </div>
      )}

      <form method="get" action="/bonos" className="card">
        <h3>Regalo</h3>
        <BonusFields
          rewardGroups={rewardGroups}
          defaults={{
            name: parsed.raw.name,
            kind: parsed.raw.kind,
            amount: parsed.raw.amount,
            points: parsed.raw.points,
            rewardItemId: parsed.raw.rewardItemId,
            message: parsed.raw.message,
            expiresDays: parsed.raw.expiresDays,
            notify: parsed.raw.notify,
          }}
        />

        <SegmentFields segment={segment} merchants={merchants} showPresets />

        <div className="inline-actions">
          <button type="submit" name="review" value="1">
            Calcular alcance
          </button>
          <a className="button secondary-link" href="/bonos">
            Empezar de nuevo
          </a>
        </div>
      </form>

      {reach ? (
        <div className="card confirm-card" id="confirmar">
          <h3>Alcance y confirmación</h3>
          <p className="text-dim" style={{ marginTop: 0 }}>
            Para: {segmentSummary(segment)}
          </p>
          <SegmentReach preview={reach.preview} error={reach.error} />
          {reach.preview && (
            <div style={{ marginTop: 16 }}>
              {!input ? (
                <p className="error">{parsed.error}</p>
              ) : people === 0 ? (
                <p className="error">Nadie cumple estos filtros: ajústalos antes de entregar.</p>
              ) : (
                <>
                  <p>
                    Se entregará <strong>{what}</strong> a hasta <strong>{formatInt(people)}</strong> personas (quien ya
                    recibió este mismo bono no lo recibe de nuevo).{" "}
                    {input.notify ? "Se les avisará por push." : "No se enviará aviso push."}
                  </p>
                  {input.message && <p className="text-dim">Mensaje: “{input.message}”</p>}
                  <ActionForm
                    action={grantBonus}
                    confirm={`¿Entregar ${what} a ${formatInt(people)} personas? No se puede deshacer.`}
                    submitLabel="Entregar"
                    pendingLabel="Entregando…"
                  >
                    {Object.entries({ ...bonusToFields(input), ...segmentToFields(segment) }).map(([name, value]) => (
                      <input key={name} type="hidden" name={name} value={value} />
                    ))}
                  </ActionForm>
                  <p className="text-dim">Si cambias el regalo o los filtros, vuelve a “Calcular alcance” antes de entregar.</p>
                </>
              )}
            </div>
          )}
        </div>
      ) : (
        <div className="card">
          <ConsentNote />
        </div>
      )}

      <div className="card">
        <h3>Historial</h3>
        {historyError ? (
          <p className="error">No se pudo leer el historial: {historyError.message}</p>
        ) : (history ?? []).length === 0 ? (
          <p className="text-dim">Todavía no se ha entregado ningún bono.</p>
        ) : (
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>Fecha</th>
                  <th>Bono</th>
                  <th>Para</th>
                  <th>Recibieron</th>
                  <th>Canjeados</th>
                  <th>Estado</th>
                </tr>
              </thead>
              <tbody>
                {(history ?? []).map((row) => {
                  const kind = toBonusKind(row.kind);
                  return (
                    <tr key={row.id}>
                      <td>{formatDateTime(row.granted_at ?? row.created_at)}</td>
                      <td>
                        <strong>{row.name}</strong>
                        <div className="text-dim">
                          {BONUS_KIND_LABELS[kind]}: {bonusValue(row)}
                        </div>
                        {row.message && <div className="text-dim">“{row.message}”</div>}
                        <div className="text-dim">{row.notify ? "Con aviso push" : "Sin aviso push"}</div>
                      </td>
                      <td className="text-dim">{segmentSummary(segmentFromJson(row.segment))}</td>
                      <td>{formatInt(row.granted_count)}</td>
                      <td>
                        {kind === "cupon" ? (
                          <>
                            {formatInt(redeemedByBonus.get(row.id) ?? 0)}
                            {row.granted_count > 0 && (
                              <div className="text-dim">
                                {Math.round(((redeemedByBonus.get(row.id) ?? 0) / row.granted_count) * 100)} %
                              </div>
                            )}
                          </>
                        ) : (
                          <span className="text-dim">—</span>
                        )}
                      </td>
                      <td>
                        <span className={`badge bonus-${row.status}`}>{row.status === "granted" ? "Entregado" : "Sin entregar"}</span>
                        {row.status === "draft" && (
                          <form action={retryBonus.bind(null, row.id)} style={{ marginTop: 6 }}>
                            <button type="submit" className="secondary">
                              Reintentar entrega
                            </button>
                          </form>
                        )}
                      </td>
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

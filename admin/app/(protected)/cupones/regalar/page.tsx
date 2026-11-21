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
import { createGiftCoupon } from "../actions";
import CouponTabs from "@/components/CouponTabs";
import CouponSettlement from "@/components/CouponSettlement";

export const dynamic = "force-dynamic";

type SearchParams = Record<string, string | string[] | undefined>;

type MerchantRef = { name: string; status: string | null; reward_currency: string | null };

type RewardItemRow = {
  id: string;
  name: string;
  points_cost: number;
  status: string;
  audience: string | null;
  free_benefit: boolean | null;
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
  max_recipients: number | null;
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
  return `${item?.name ?? "Cupón"}${merchant ? ` en ${merchant.name}` : ""} (vence en ${row.expires_days} días)`;
}

// Regalar cupones (antes "Bonos y regalos"): un cupon de un comercio
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
  const [merchants, { data: items }, { data: history, error: historyError }, reach, { data: couponMerchants }] = await Promise.all([
    fetchSegmentMerchants(),
    supabase
      .from("reward_items")
      .select("id, name, points_cost, status, audience, free_benefit, partner_merchants(name, status, reward_currency)")
      .eq("status", "active")
      .order("name")
      .returns<RewardItemRow[]>(),
    supabase
      .from("bonus_grants")
      .select(
        "id, name, kind, amount, reward_item_id, message, expires_days, segment, notify, status, granted_count, max_recipients, created_at, granted_at, reward_items(name, partner_merchants(name))"
      )
      .order("created_at", { ascending: false })
      .limit(50)
      .returns<BonusRow[]>(),
    review ? fetchSegmentPreview(segment) : Promise.resolve(null),
    supabase
      .from("partner_merchants")
      .select("id, name, status")
      .order("name")
      .returns<{ id: string; name: string; status: string }[]>(),
  ]);

  // Cupones (y productos del catalogo) agrupados por comercio activo.
  const groups = new Map<string, RewardOptionGroup>();
  const sortedItems = [...(items ?? [])]
    .filter((item) => !item.free_benefit)
    .sort((a, b) => Number(b.audience === "cupon") - Number(a.audience === "cupon"));
  for (const item of sortedItems) {
    const merchant = embedded(item.partner_merchants);
    if (!merchant || (merchant.status && merchant.status !== "active")) continue;
    const label = item.audience === "cupon" ? `🎟️ Cupones de ${merchant.name}` : `${merchant.name} (productos)`;
    const group = groups.get(label) ?? { merchant: label, items: [] };
    group.items.push({
      id: item.id,
      name: item.name,
      value: formatRewardValue(item.points_cost, toRewardCurrency(merchant.reward_currency)),
    });
    groups.set(label, group);
  }
  const rewardGroups = [...groups.values()].sort(
    (a, b) => Number(b.merchant.startsWith("🎟️")) - Number(a.merchant.startsWith("🎟️")) || a.merchant.localeCompare(b.merchant, "es")
  );
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
        : `${itemLabel.get(input.reward_item_id ?? "") ?? "un cupón"} (vence en ${input.expires_days} días)`
    : "";
  const toGive = input?.max_recipients ? Math.min(people, input.max_recipients) : people;

  return (
    <>
      <h1>Cupones</h1>
      <CouponTabs active="regalar" />
      <p className="text-dim">
        Regala un cupón a quien tú quieras: a clientes específicos por correo (por ejemplo, los que cumplieron su meta) o
        a un grupo, como campaña. Si compraste 5 cupones de $20 en un comercio, pon 5 y solo se entregan esos. A cada
        persona le llega un aviso y el cupón aparece en “Mis cupones y canjes” con su código para caja.
      </p>

      <div className="card">
        <h3>1. Crear un cupón (si aún no existe)</h3>
        <ActionForm action={createGiftCoupon} className="grid-form" submitLabel="Crear cupón" resetOnSuccess>
          <div className="field">
            <label>Comercio</label>
            <select name="merchant_id" required defaultValue="">
              <option value="" disabled>
                Elige el comercio
              </option>
              {(couponMerchants ?? []).map((merchant) => (
                <option key={merchant.id} value={merchant.id}>
                  {merchant.name}
                  {merchant.status === "active" ? "" : " (oculto)"}
                </option>
              ))}
            </select>
          </div>
          <div className="field">
            <label>Valor del cupón (US$)</label>
            <input type="number" name="value" required min={1} step={0.01} inputMode="decimal" placeholder="20" />
          </div>
          <div className="field">
            <label>Nombre del cupón (opcional)</label>
            <input type="text" name="coupon_name" maxLength={120} placeholder="Cupón de $20" />
          </div>
          <div className="field">
            <label>Condiciones en caja (opcional)</label>
            <input type="text" name="conditions" maxLength={500} placeholder="En compras desde $40. No acumulable." />
          </div>
          <div className="field" style={{ gridColumn: "1 / -1" }}>
            <label>Imagen del cupón (opcional, sale en el aviso y en la app)</label>
            <input type="file" name="photo" accept="image/jpeg,image/png,image/webp" />
          </div>
        </ActionForm>
      </div>

      {doneMessage && (
        <div className="card" style={{ borderColor: "var(--success)" }}>
          <strong className="success-text">Listo.</strong> {doneMessage}
        </div>
      )}

      <form method="get" action="/cupones/regalar" className="card" id="regalo">
        <h3>2. ¿Qué cupón y a quién?</h3>
        <BonusFields
          couponOnly
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
            maxRecipients: parsed.raw.maxRecipients,
          }}
        />

        <SegmentFields segment={segment} merchants={merchants} showPresets allowEmails />

        <div className="inline-actions">
          <button type="submit" name="review" value="1">
            Calcular alcance
          </button>
          <a className="button secondary-link" href="/cupones/regalar">
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
                    Se entregará <strong>{what}</strong> a <strong>{formatInt(toGive)}</strong> personas
                    {input.max_recipients && people > input.max_recipients
                      ? ` (elegidas al azar entre ${formatInt(people)} que cumplen)`
                      : ""}
                    . Nadie lo recibe dos veces.{" "}
                    {input.notify ? "Les llegará un aviso en el teléfono." : "No se enviará aviso."}
                  </p>
                  {input.message && <p className="text-dim">Mensaje: “{input.message}”</p>}
                  <ActionForm
                    action={grantBonus}
                    confirm={`¿Regalar ${what} a ${formatInt(toGive)} personas? No se puede deshacer.`}
                    submitLabel="Regalar cupones"
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
          <p className="text-dim">Todavía no has regalado cupones.</p>
        ) : (
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>Fecha</th>
                  <th>Regalo</th>
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
                      <td>
                        {formatInt(row.granted_count)}
                        {row.max_recipients ? ` de ${formatInt(row.max_recipients)}` : ""}
                      </td>
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

      <CouponSettlement />
    </>
  );
}

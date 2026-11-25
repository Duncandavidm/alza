import Link from "next/link";
import { notFound } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase-admin";
import ActionForm from "@/components/ActionForm";
import MerchantFieldsInputs from "@/components/MerchantFieldsInputs";
import RewardPreviewCard from "@/components/RewardPreviewCard";
import { formatCashback, formatDateTime, formatDecimal, formatInt, formatMoney } from "@/lib/format";
import { benefitLimitLabel, rewardTypeLabel, toRewardType } from "@/lib/reward-type";
import { Kpi } from "@/components/Charts";
import { formatRewardValue, type RewardCurrency, toRewardCurrency } from "@/lib/currency";
import { fetchMerchantCategories } from "@/lib/categories";
import {
  createOffer,
  createRewardItem,
  deleteRewardItem,
  generateRedeemPin,
  sendMerchantPush,
  setRewardItemStatus,
  updateMerchant,
  updateOfferStatus,
  updateRewardItem,
} from "./actions";
import RewardItemForm from "./RewardItemForm";
import RedeemPinCard from "./RedeemPinCard";
import BranchesCard from "./BranchesCard";
import LocationCard from "./LocationCard";

type Merchant = {
  id: string;
  name: string;
  ruc: string;
  status: "active" | "paused";
  category: string | null;
  address: string | null;
  maps_url: string | null;
  logo_url: string | null;
  redeem_pin_set_at: string | null;
  reward_currency: RewardCurrency | null;
};
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
type RewardItem = {
  id: string;
  name: string;
  description: string | null;
  photo_url: string | null;
  points_cost: number;
  status: "active" | "paused" | "agotado";
  sort_order: number;
  reward_type: string | null;
  discount_value: number | string | null;
  max_redemptions: number | null;
  free_benefit: boolean | null;
  per_user_limit: number | null;
  per_user_period: string | null;
};

type BenefitReport = {
  days: number;
  uses: number;
  customers: number;
  new_customers: number;
  with_receipt: number;
  receipt_rate: number | null;
  avg_ticket: number | null;
  total_sales: number;
  by_item: { name: string; uses: number; customers: number; with_receipt: number; avg_ticket: number | null; total_sales: number }[];
};

export default async function MerchantDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = supabaseAdmin();

  const { data: merchant } = await supabase
    .from("partner_merchants")
    .select("id, name, ruc, status, category, address, maps_url, logo_url, redeem_pin_set_at, reward_currency")
    .eq("id", id)
    .maybeSingle<Merchant>();
  if (!merchant) notFound();

  const [{ data: offers }, { data: items }, { data: delivered }, { data: usedRows }, { data: benefitReportData }, categories] = await Promise.all([
    supabase
      .from("partner_merchant_offers")
      .select("id, offer_type, value, min_amount, starts_at, ends_at, budget_total_points, budget_spent_points, status")
      .eq("merchant_id", id)
      .order("starts_at", { ascending: false })
      .returns<Offer[]>(),
    supabase
      .from("reward_items")
      .select(
        // "*": incluye las columnas de 0085 cuando ya existen (dias, compra
        // minima, quien paga, fechas) sin fallar antes de la migracion.
        "*"
      )
      .eq("merchant_id", id)
      .order("sort_order", { ascending: true })
      .order("created_at", { ascending: true })
      .returns<RewardItem[]>(),
    supabase
      .from("reward_redemptions")
      .select("delivered_via")
      .eq("merchant_id", id)
      .eq("status", "entregado")
      .returns<{ delivered_via: string | null }[]>(),
    // Codigos que gastan cupo (igual que reward_item_used en 0067):
    // entregados o emitidos sin vencer, sin contar los regalos de MonAvi.
    supabase
      .from("reward_redemptions")
      .select("reward_item_id")
      .eq("merchant_id", id)
      .neq("source", "regalo")
      .in("status", ["emitido", "entregado"])
      .or(`status.eq.entregado,expires_at.gt.${new Date().toISOString()}`)
      .limit(100000)
      .returns<{ reward_item_id: string }[]>(),
    // Visitas y ticket promedio que trajeron los descuentos (0067).
    supabase.rpc("merchant_benefit_report", { p_merchant_id: id, p_days: 90 }),
    fetchMerchantCategories(),
  ]);
  const benefitReport = (benefitReportData ?? null) as BenefitReport | null;
  const usedByItem = new Map<string, number>();
  for (const row of usedRows ?? []) usedByItem.set(row.reward_item_id, (usedByItem.get(row.reward_item_id) ?? 0) + 1);
  const deliveredCount = (delivered ?? []).length;
  const deliveredAtCounter = (delivered ?? []).filter((row) => row.delivered_via === "comercio").length;

  const rewardItems = items ?? [];
  const hasMaps = Boolean(merchant.maps_url);
  const currency = toRewardCurrency(merchant.reward_currency);

  return (
    <>
      <p className="text-dim">
        <Link href="/merchants">← Comercios aliados</Link>
      </p>
      <div style={{ display: "flex", gap: 14, alignItems: "center", marginBottom: 8 }}>
        {merchant.logo_url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={merchant.logo_url} alt="" className="thumb round large" />
        ) : (
          <span className="thumb round large placeholder">{merchant.name.slice(0, 1).toUpperCase()}</span>
        )}
        <div>
          <h1 style={{ margin: 0 }}>{merchant.name}</h1>
          <p className="text-dim" style={{ margin: "4px 0 0" }}>
            RUC {merchant.ruc}
            {merchant.category ? ` · ${merchant.category}` : ""} ·{" "}
            <span className={`badge ${merchant.status}`}>
              {merchant.status === "active" ? "publicado en la app" : "oculto (sin publicar)"}
            </span>
            {merchant.maps_url && (
              <>
                {" "}
                ·{" "}
                <a href={merchant.maps_url} target="_blank" rel="noreferrer">
                  Abrir en Google Maps
                </a>
              </>
            )}
          </p>
        </div>
      </div>

      <div className="card">
        <h3>Ficha del comercio</h3>
        <p className="text-dim">Esto es lo que ven los clientes en la app: nombre, logo, categoría, dirección y “Cómo llegar”.</p>
        <ActionForm action={updateMerchant.bind(null, merchant.id)} className="grid-form" submitLabel="Guardar ficha">
          <MerchantFieldsInputs
            defaults={merchant}
            itemsCount={rewardItems.length}
            categories={categories.map((category) => category.name)}
          />
          <div className="field">
            <label>¿Sale en la app?</label>
            <select name="status" defaultValue={merchant.status}>
              <option value="active">Publicado (sale en la app)</option>
              <option value="paused">Oculto (todavía no sale)</option>
            </select>
          </div>
        </ActionForm>
      </div>

      <div className="card">
        <h3>PIN de canje en caja</h3>
        <p className="text-dim">
          El cajero valida el código del cliente en{" "}
          <a href="/canjear" target="_blank" rel="noreferrer">
            monavi.maday.app/canjear
          </a>{" "}
          con este PIN de 6 dígitos, desde cualquier celular. Solo se guarda cifrado: se muestra una única vez al
          generarlo. Canjes entregados: {deliveredCount} ({deliveredAtCounter} validados en caja). El comercio entrega el
          producto sin costo para MonAvi.
        </p>
        <RedeemPinCard
          action={generateRedeemPin.bind(null, merchant.id)}
          merchantName={merchant.name}
          pinSetAtLabel={merchant.redeem_pin_set_at ? formatDateTime(merchant.redeem_pin_set_at) : null}
        />
      </div>

      <BranchesCard merchantId={merchant.id} merchantName={merchant.name} mainAddress={merchant.address} />

      <LocationCard merchantId={merchant.id} hasMapsUrl={Boolean(merchant.maps_url)} />

      <div className="card">
        <h3>Productos canjeables</h3>
        <p className="text-dim">
          Lo que los clientes pueden canjear{" "}
          {currency === "puntos" ? "con sus puntos (buenos hábitos)" : "con su cashback (dólares de facturas)"} en este
          comercio. La foto del producto es lo más visible en la
          app: usa una foto horizontal, bien iluminada y sin texto encima.
          {!hasMaps && " Falta el enlace de Google Maps en la ficha: sin él, el botón “Cómo llegar” no funciona."}
        </p>

        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Foto</th>
                <th>Producto</th>
                <th>{currency === "puntos" ? "Puntos" : "Valor en cashback"}</th>
                <th>Canjes</th>
                <th>Estado</th>
                <th>Orden</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {rewardItems.map((item) => (
                <tr key={item.id}>
                  <td>
                    {item.photo_url ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={item.photo_url} alt="" className="thumb wide" />
                    ) : (
                      <span className="thumb wide placeholder">Sin foto</span>
                    )}
                  </td>
                  <td>
                    {item.name}
                    {item.reward_type && item.reward_type !== "producto" && (
                      <div className="text-dim">{rewardTypeLabel(toRewardType(item.reward_type))}</div>
                    )}
                    {item.description && <div className="text-dim">{item.description}</div>}
                  </td>
                  <td>
                    {item.free_benefit
                      ? `Por ser de MonAvi · ${benefitLimitLabel(item.per_user_limit, item.per_user_period)}`
                      : formatRewardValue(item.points_cost, currency)}
                  </td>
                  <td>
                    {item.max_redemptions
                      ? `${formatInt(usedByItem.get(item.id) ?? 0)} de ${formatInt(item.max_redemptions)}`
                      : `${formatInt(usedByItem.get(item.id) ?? 0)} · sin límite`}
                  </td>
                  <td>
                    <span className={`badge ${item.status}`}>
                      {item.status === "active" ? "activo" : item.status === "agotado" ? "agotado" : "pausado"}
                    </span>
                  </td>
                  <td>{item.sort_order}</td>
                  <td>
                    <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
                      <form
                        action={setRewardItemStatus.bind(
                          null,
                          merchant.id,
                          item.id,
                          item.status === "paused" ? "active" : "paused"
                        )}
                      >
                        <button type="submit" className="secondary">
                          {item.status === "paused" ? "Reactivar" : "Pausar"}
                        </button>
                      </form>
                      <ActionForm
                        action={deleteRewardItem.bind(null, merchant.id, item.id)}
                        confirm={`¿Eliminar “${item.name}”? Esta acción no se puede deshacer.`}
                        submitLabel="Eliminar"
                        submitClassName="danger"
                        pendingLabel="Eliminando…"
                        inline
                      >
                        {null}
                      </ActionForm>
                    </div>
                  </td>
                </tr>
              ))}
              {rewardItems.length === 0 && (
                <tr>
                  <td colSpan={7} className="text-dim">
                    Este comercio todavía no tiene productos canjeables.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        {rewardItems.map((item) => (
          <details key={item.id} className="edit-details">
            <summary>Editar “{item.name}”</summary>
            <RewardItemForm
              action={updateRewardItem.bind(null, merchant.id, item.id)}
              merchantName={merchant.name}
              logoUrl={merchant.logo_url}
              hasMaps={hasMaps}
              currency={currency}
              item={item}
              submitLabel="Guardar producto"
            />
          </details>
        ))}

        <h3 style={{ marginTop: 20 }}>Nuevo producto canjeable</h3>
        <RewardItemForm
          action={createRewardItem.bind(null, merchant.id)}
          merchantName={merchant.name}
          logoUrl={merchant.logo_url}
          hasMaps={hasMaps}
          currency={currency}
          submitLabel="Agregar producto"
        />

        {rewardItems.length > 0 && (
          <>
            <h3 style={{ marginTop: 20 }}>Así se ven en la app</h3>
            <div className="reward-preview-grid">
              {rewardItems.map((item) => (
                <RewardPreviewCard
                  key={item.id}
                  merchantName={merchant.name}
                  logoUrl={merchant.logo_url}
                  productName={item.name}
                  photoUrl={item.photo_url}
                  value={item.points_cost}
                  currency={currency}
                  description={item.description}
                  hasMaps={hasMaps}
                  paused={item.status !== "active" || merchant.status === "paused"}
                  isFree={Boolean(item.free_benefit)}
                  pausedLabel={item.status === "agotado" ? "Agotado — se llegó al límite, no se ve en la app" : undefined}
                />
              ))}
            </div>
          </>
        )}
      </div>

      <div className="card">
        <h3>Avisar a los clientes</h3>
        <p className="text-dim">
          Llega a quien aceptó recibir ofertas, con el logo del comercio. Cada persona recibe su propio mensaje: el
          descuento por ser de MonAvi y cuánto cashback le falta para el premio más barato (o que ya puede reclamarlo). Por
          ejemplo: <em>“Tienes 10% de descuento en {merchant.name} 🎉 · Te faltan $1.20 de cashback para un capuchino.”</em>
        </p>
        <ActionForm
          action={sendMerchantPush.bind(null, merchant.id)}
          className="grid-form"
          submitLabel="Enviar aviso"
          pendingLabel="Enviando…"
          confirm={`¿Enviar el aviso de ${merchant.name} a los clientes?`}
        >
          <div className="field">
            <label>Título propio (opcional)</label>
            <input type="text" name="title" maxLength={80} placeholder="Vacío = se arma solo" />
          </div>
          <div className="field">
            <label>Frase antes del mensaje (opcional)</label>
            <input type="text" name="body" maxLength={240} placeholder="¡Solo este fin de semana!" />
          </div>
        </ActionForm>
      </div>

      <div className="card">
        <h3>Resultados de los descuentos (últimos 90 días)</h3>
        <p className="text-dim">
          Cada uso en caja es una visita. Se le suma la factura que esa persona escaneó en este comercio cerca de esa hora
          (de 3 h antes a 12 h después) para calcular el ticket promedio. &quot;Clientes nuevos&quot;: no habían escaneado
          facturas aquí antes de su primer descuento.
        </p>
        {benefitReport && Number(benefitReport.uses) > 0 ? (
          <>
            <div className="kpi-grid">
              <Kpi label="Visitas con descuento" value={formatInt(benefitReport.uses)} />
              <Kpi label="Clientes" value={formatInt(benefitReport.customers)} hint={`${formatInt(benefitReport.new_customers)} nuevos`} />
              <Kpi
                label="Ticket promedio"
                value={benefitReport.avg_ticket === null ? "—" : formatMoney(benefitReport.avg_ticket)}
                hint={`${formatInt(benefitReport.with_receipt)} con factura escaneada`}
              />
              <Kpi label="Ventas con factura" value={formatMoney(benefitReport.total_sales)} />
              <Kpi
                label="Pidieron factura"
                value={benefitReport.receipt_rate === null ? "—" : `${formatDecimal(benefitReport.receipt_rate, 1)}%`}
              />
            </div>
            {benefitReport.by_item.length > 1 && (
              <div className="table-scroll" style={{ marginTop: 12 }}>
                <table>
                  <thead>
                    <tr>
                      <th>Descuento</th>
                      <th>Visitas</th>
                      <th>Clientes</th>
                      <th>Con factura</th>
                      <th>Ticket promedio</th>
                      <th>Ventas</th>
                    </tr>
                  </thead>
                  <tbody>
                    {benefitReport.by_item.map((row) => (
                      <tr key={row.name}>
                        <td>{row.name}</td>
                        <td>{formatInt(row.uses)}</td>
                        <td>{formatInt(row.customers)}</td>
                        <td>{formatInt(row.with_receipt)}</td>
                        <td>{row.avg_ticket === null ? "—" : formatMoney(row.avg_ticket)}</td>
                        <td>{formatMoney(row.total_sales)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </>
        ) : (
          <p className="text-dim">Todavía no hay descuentos usados en este comercio.</p>
        )}
      </div>

      <div className="card">
        <h3>Nueva oferta de cashback</h3>
        <form action={createOffer.bind(null, merchant.id)} className="grid-form">
          <div className="field">
            <label>Tipo</label>
            <select name="offer_type" defaultValue="percent">
              <option value="percent">% de cashback sobre la compra</option>
              <option value="fixed">Cashback fijo por compra (US$)</option>
            </select>
          </div>
          <div className="field">
            <label>Valor (% de cashback, o US$ fijos)</label>
            <input type="number" name="value" step="0.01" min="0.01" required />
          </div>
          <div className="field">
            <label>Compra mínima en US$ (opcional)</label>
            <input type="number" name="min_amount" step="0.01" min="0" />
          </div>
          <div className="field">
            <label>Presupuesto total de cashback en US$ (opcional)</label>
            <input type="number" name="budget_total_points" step="0.01" min="0.01" inputMode="decimal" />
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

      <div className="card table-scroll">
        <h3>Ofertas de cashback</h3>
        <table>
          <thead>
            <tr>
              <th>Tipo</th>
              <th>Valor</th>
              <th>Mínimo</th>
              <th>Presupuesto</th>
              <th>Termina</th>
              <th>Estado</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {(offers ?? []).map((offer) => (
              <tr key={offer.id}>
                <td>{offer.offer_type === "percent" ? "% de la compra" : "Fijo por compra"}</td>
                <td>
                  {offer.offer_type === "percent"
                    ? `${Number(offer.value).toLocaleString("es-PA", { maximumFractionDigits: 2 })} % de cashback`
                    : `${formatCashback(offer.value)} de cashback`}
                </td>
                <td>{offer.min_amount !== null ? formatMoney(offer.min_amount) : "—"}</td>
                <td>
                  {offer.budget_total_points !== null
                    ? `${formatCashback(offer.budget_spent_points)} / ${formatCashback(offer.budget_total_points)}`
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
                  Sin ofertas todavía.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </>
  );
}

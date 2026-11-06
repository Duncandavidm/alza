import Link from "next/link";
import { notFound } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase-admin";
import ActionForm from "@/components/ActionForm";
import MerchantFieldsInputs from "@/components/MerchantFieldsInputs";
import RewardPreviewCard from "@/components/RewardPreviewCard";
import { formatPoints } from "@/lib/format";
import {
  createOffer,
  createRewardItem,
  deleteRewardItem,
  setRewardItemStatus,
  updateMerchant,
  updateOfferStatus,
  updateRewardItem,
} from "./actions";
import RewardItemForm from "./RewardItemForm";

type Merchant = {
  id: string;
  name: string;
  ruc: string;
  status: "active" | "paused";
  category: string | null;
  address: string | null;
  maps_url: string | null;
  logo_url: string | null;
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
  status: "active" | "paused";
  sort_order: number;
};

export default async function MerchantDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = supabaseAdmin();

  const { data: merchant } = await supabase
    .from("partner_merchants")
    .select("id, name, ruc, status, category, address, maps_url, logo_url")
    .eq("id", id)
    .maybeSingle<Merchant>();
  if (!merchant) notFound();

  const [{ data: offers }, { data: items }] = await Promise.all([
    supabase
      .from("partner_merchant_offers")
      .select("id, offer_type, value, min_amount, starts_at, ends_at, budget_total_points, budget_spent_points, status")
      .eq("merchant_id", id)
      .order("starts_at", { ascending: false })
      .returns<Offer[]>(),
    supabase
      .from("reward_items")
      .select("id, name, description, photo_url, points_cost, status, sort_order")
      .eq("merchant_id", id)
      .order("sort_order", { ascending: true })
      .order("created_at", { ascending: true })
      .returns<RewardItem[]>(),
  ]);

  const rewardItems = items ?? [];
  const hasMaps = Boolean(merchant.maps_url);

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
            <span className={`badge ${merchant.status}`}>{merchant.status === "active" ? "activo" : "pausado"}</span>
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
          <MerchantFieldsInputs defaults={merchant} />
          <div className="field">
            <label>Estado</label>
            <select name="status" defaultValue={merchant.status}>
              <option value="active">Activo</option>
              <option value="paused">Pausado (oculto en la app)</option>
            </select>
          </div>
        </ActionForm>
      </div>

      <div className="card">
        <h3>Productos canjeables</h3>
        <p className="text-dim">
          Lo que los clientes pueden canjear con sus puntos en este comercio. La foto del producto es lo más visible en la
          app: usa una foto horizontal, bien iluminada y sin texto encima.
          {!hasMaps && " Falta el enlace de Google Maps en la ficha: sin él, el botón “Cómo llegar” no funciona."}
        </p>

        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Foto</th>
                <th>Producto</th>
                <th>Puntos</th>
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
                    {item.description && <div className="text-dim">{item.description}</div>}
                  </td>
                  <td>{formatPoints(item.points_cost)}</td>
                  <td>
                    <span className={`badge ${item.status}`}>{item.status === "active" ? "activo" : "pausado"}</span>
                  </td>
                  <td>{item.sort_order}</td>
                  <td>
                    <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
                      <form
                        action={setRewardItemStatus.bind(
                          null,
                          merchant.id,
                          item.id,
                          item.status === "active" ? "paused" : "active"
                        )}
                      >
                        <button type="submit" className="secondary">
                          {item.status === "active" ? "Pausar" : "Reactivar"}
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
                  <td colSpan={6} className="text-dim">
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
                  pointsCost={item.points_cost}
                  description={item.description}
                  hasMaps={hasMaps}
                  paused={item.status === "paused" || merchant.status === "paused"}
                />
              ))}
            </div>
          </>
        )}
      </div>

      <div className="card">
        <h3>Nueva oferta de puntos</h3>
        <form action={createOffer.bind(null, merchant.id)} className="grid-form">
          <div className="field">
            <label>Tipo</label>
            <select name="offer_type" defaultValue="percent">
              <option value="percent">% en puntos por dólar</option>
              <option value="fixed">Puntos fijos por compra</option>
            </select>
          </div>
          <div className="field">
            <label>Valor (puntos por dólar, o puntos fijos)</label>
            <input type="number" name="value" step="0.01" min="0.01" required />
          </div>
          <div className="field">
            <label>Compra mínima (opcional)</label>
            <input type="number" name="min_amount" step="0.01" min="0" />
          </div>
          <div className="field">
            <label>Presupuesto total de puntos (opcional)</label>
            <input type="number" name="budget_total_points" step="1" min="1" />
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
        <h3>Ofertas de puntos</h3>
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
                <td>{offer.offer_type === "percent" ? "% por dólar" : "Fijo"}</td>
                <td>{offer.value}</td>
                <td>{offer.min_amount ?? "—"}</td>
                <td>
                  {offer.budget_total_points !== null
                    ? `${offer.budget_spent_points} / ${offer.budget_total_points} pts`
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

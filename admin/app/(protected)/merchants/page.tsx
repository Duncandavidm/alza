import Link from "next/link";
import { supabaseAdmin } from "@/lib/supabase-admin";
import ActionForm from "@/components/ActionForm";
import MerchantFieldsInputs from "@/components/MerchantFieldsInputs";
import { createMerchant, updateMerchantStatus } from "./actions";

type Merchant = {
  id: string;
  name: string;
  ruc: string;
  status: "active" | "paused";
  category: string | null;
  logo_url: string | null;
  maps_url: string | null;
};

export default async function MerchantsPage() {
  const supabase = supabaseAdmin();
  const [{ data: merchants }, { data: items }] = await Promise.all([
    supabase
      .from("partner_merchants")
      .select("id, name, ruc, status, category, logo_url, maps_url")
      .order("name", { ascending: true })
      .returns<Merchant[]>(),
    supabase.from("reward_items").select("merchant_id, status").returns<{ merchant_id: string; status: string }[]>(),
  ]);

  const activeItemsByMerchant = new Map<string, number>();
  for (const item of items ?? []) {
    if (item.status !== "active") continue;
    activeItemsByMerchant.set(item.merchant_id, (activeItemsByMerchant.get(item.merchant_id) ?? 0) + 1);
  }

  return (
    <>
      <h1>Comercios aliados</h1>
      <p className="text-dim">
        La ficha de cada comercio (logo, categoría, dirección y enlace de Google Maps) es lo que ven los clientes en la
        app junto a sus productos canjeables. Las solicitudes que llegan desde la landing están en{" "}
        <Link href="/applications">Solicitudes</Link>.
      </p>

      <div className="card">
        <h3>Nuevo comercio</h3>
        <ActionForm action={createMerchant} className="grid-form" submitLabel="Crear comercio" pendingLabel="Creando…">
          <MerchantFieldsInputs />
        </ActionForm>
      </div>

      <div className="card table-scroll">
        <table>
          <thead>
            <tr>
              <th></th>
              <th>Nombre</th>
              <th>RUC</th>
              <th>Categoría</th>
              <th>Productos activos</th>
              <th>Estado</th>
              <th></th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {(merchants ?? []).map((merchant) => (
              <tr key={merchant.id}>
                <td>
                  {merchant.logo_url ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={merchant.logo_url} alt="" className="thumb round" />
                  ) : (
                    <span className="thumb round placeholder">{merchant.name.slice(0, 1).toUpperCase()}</span>
                  )}
                </td>
                <td>
                  <Link href={`/merchants/${merchant.id}`}>{merchant.name}</Link>
                  {!merchant.maps_url && <div className="text-dim">Falta enlace de Maps</div>}
                </td>
                <td>{merchant.ruc}</td>
                <td className="text-dim">{merchant.category ?? "—"}</td>
                <td>{activeItemsByMerchant.get(merchant.id) ?? 0}</td>
                <td>
                  <span className={`badge ${merchant.status}`}>{merchant.status === "active" ? "activo" : "pausado"}</span>
                </td>
                <td>
                  <Link href={`/merchants/${merchant.id}`}>Ficha, productos y ofertas</Link>
                </td>
                <td>
                  <form action={updateMerchantStatus.bind(null, merchant.id, merchant.status === "active" ? "paused" : "active")}>
                    <button type="submit" className="secondary">
                      {merchant.status === "active" ? "Pausar" : "Reactivar"}
                    </button>
                  </form>
                </td>
              </tr>
            ))}
            {(merchants ?? []).length === 0 && (
              <tr>
                <td colSpan={8} className="text-dim">
                  Todavía no hay comercios aliados.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </>
  );
}

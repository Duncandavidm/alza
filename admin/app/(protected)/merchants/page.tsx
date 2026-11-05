import Link from "next/link";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { createMerchant, updateMerchantStatus } from "./actions";

type Merchant = {
  id: string;
  name: string;
  ruc: string;
  status: "active" | "paused";
};

export default async function MerchantsPage() {
  const supabase = supabaseAdmin();
  const { data: merchants } = await supabase
    .from("partner_merchants")
    .select("id, name, ruc, status")
    .order("name", { ascending: true })
    .returns<Merchant[]>();

  return (
    <>
      <h1>Comercios aliados</h1>

      <div className="card">
        <h3>Nuevo comercio</h3>
        <form action={createMerchant} className="grid-form">
          <div className="field">
            <label>Nombre</label>
            <input type="text" name="name" required />
          </div>
          <div className="field">
            <label>RUC</label>
            <input type="text" name="ruc" required />
          </div>
          <div className="field" style={{ alignSelf: "end" }}>
            <button type="submit">Crear</button>
          </div>
        </form>
      </div>

      <div className="card">
        <table>
          <thead>
            <tr>
              <th>Nombre</th>
              <th>RUC</th>
              <th>Estado</th>
              <th>Ofertas</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {(merchants ?? []).map((merchant) => (
              <tr key={merchant.id}>
                <td>{merchant.name}</td>
                <td>{merchant.ruc}</td>
                <td>
                  <span className={`badge ${merchant.status}`}>{merchant.status}</span>
                </td>
                <td>
                  <Link href={`/merchants/${merchant.id}`}>Ver / administrar ofertas</Link>
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
                <td colSpan={5} className="text-dim">
                  Todavia no hay comercios aliados.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </>
  );
}

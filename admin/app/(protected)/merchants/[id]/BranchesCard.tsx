import ActionForm from "@/components/ActionForm";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { formatDateTime, formatInt } from "@/lib/format";
import RedeemPinCard from "./RedeemPinCard";
import { createBranch, deleteBranch, generateBranchPin, setBranchStatus, updateBranch } from "./actions";

type Branch = {
  id: string;
  name: string;
  address: string | null;
  maps_url: string | null;
  status: "active" | "paused";
  redeem_pin_set_at: string | null;
};

/// Sucursales del comercio: direcciones extra (mismo RUC), cada una con su
/// "Como llegar" en la app y, si se quiere, su propio PIN de caja para
/// saber en que sucursal se uso cada codigo.
export default async function BranchesCard({
  merchantId,
  merchantName,
  mainAddress,
}: {
  merchantId: string;
  merchantName: string;
  mainAddress: string | null;
}) {
  const supabase = supabaseAdmin();
  const [{ data: branches }, { data: used }] = await Promise.all([
    supabase
      .from("merchant_branches")
      .select("id, name, address, maps_url, status, redeem_pin_set_at")
      .eq("merchant_id", merchantId)
      .order("sort_order")
      .order("created_at")
      .returns<Branch[]>(),
    supabase
      .from("reward_redemptions")
      .select("branch_id")
      .eq("merchant_id", merchantId)
      .eq("status", "entregado")
      .limit(50000)
      .returns<{ branch_id: string | null }[]>(),
  ]);
  // Ubicacion (0080) en una consulta aparte: si falta la migracion, la
  // tarjeta sigue funcionando sin ella.
  const { data: located } = await supabase
    .from("merchant_branches")
    .select("id, latitude, longitude")
    .eq("merchant_id", merchantId)
    .returns<{ id: string; latitude: number | null; longitude: number | null }[]>();
  const coordsBy = new Map(
    (located ?? []).filter((row) => row.latitude !== null && row.longitude !== null).map((row) => [row.id, `${row.latitude}, ${row.longitude}`])
  );
  const usedBy = new Map<string, number>();
  for (const row of used ?? []) {
    const key = row.branch_id ?? "principal";
    usedBy.set(key, (usedBy.get(key) ?? 0) + 1);
  }

  return (
    <div className="card">
      <h3>Sucursales</h3>
      <p className="text-dim">
        Si el comercio tiene más de un local, agrégalos aquí. La dirección de la ficha es la principal. En la app, “Cómo
        llegar” deja elegir la sucursal. El cashback por factura funciona en todas porque facturan con el mismo RUC. Si le
        das un PIN a una sucursal, cada canje validado con ese PIN queda registrado en esa sucursal.
      </p>

      <div className="table-scroll">
        <table>
          <thead>
            <tr>
              <th>Sucursal</th>
              <th>Canjes en caja</th>
              <th>Estado</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>
                <strong>Principal</strong>
                <div className="text-dim">{mainAddress || "Sin dirección en la ficha"}</div>
                <div className="text-dim">PIN: el del comercio (arriba)</div>
              </td>
              <td>{formatInt(usedBy.get("principal") ?? 0)}</td>
              <td>
                <span className="badge active">activa</span>
              </td>
              <td></td>
            </tr>
            {(branches ?? []).map((branch) => (
              <tr key={branch.id}>
                <td>
                  <strong>{branch.name}</strong>
                  <div className="text-dim">{branch.address || "Sin dirección"}</div>
                  {!branch.maps_url && <div className="text-dim">Falta el enlace de Google Maps para “Cómo llegar”.</div>}
                  <div className="text-dim">
                    {coordsBy.has(branch.id) ? (
                      <>
                        📍 Ubicada para avisos por cercanía ·{" "}
                        <a href={`https://www.google.com/maps?q=${coordsBy.get(branch.id)}`} target="_blank" rel="noreferrer">
                          comprobar en el mapa
                        </a>
                      </>
                    ) : (
                      "Sin ubicación para avisos por cercanía: pon su enlace de Maps o sus coordenadas en Editar."
                    )}
                  </div>
                  <details style={{ marginTop: 6 }}>
                    <summary>Editar</summary>
                    <ActionForm action={updateBranch.bind(null, merchantId, branch.id)} className="grid-form" submitLabel="Guardar">
                      <div className="field">
                        <label>Nombre</label>
                        <input type="text" name="name" required maxLength={80} defaultValue={branch.name} />
                      </div>
                      <div className="field">
                        <label>Dirección</label>
                        <input type="text" name="address" maxLength={300} defaultValue={branch.address ?? ""} />
                      </div>
                      <div className="field" style={{ gridColumn: "1 / -1" }}>
                        <label>Enlace de Google Maps</label>
                        <input type="url" name="maps_url" maxLength={1000} defaultValue={branch.maps_url ?? ""} placeholder="https://maps.app.goo.gl/…" />
                      </div>
                      <div className="field" style={{ gridColumn: "1 / -1" }}>
                        <label>Coordenadas (opcional)</label>
                        <input type="text" name="coordinates" maxLength={1000} placeholder={coordsBy.get(branch.id) ?? "Se sacan solas del enlace de Maps · o pega 9.0123, -79.5123"} />
                        <span className="text-dim">Déjalo vacío para sacarlas del enlace. Si el enlace no las trae, en Google Maps mantén presionado el local y copia sus coordenadas.</span>
                      </div>
                    </ActionForm>
                  </details>
                  <details style={{ marginTop: 6 }}>
                    <summary>PIN de caja de esta sucursal</summary>
                    <RedeemPinCard
                      action={generateBranchPin.bind(null, merchantId, branch.id)}
                      merchantName={`${merchantName} · ${branch.name}`}
                      pinSetAtLabel={branch.redeem_pin_set_at ? formatDateTime(branch.redeem_pin_set_at) : null}
                    />
                  </details>
                </td>
                <td>{formatInt(usedBy.get(branch.id) ?? 0)}</td>
                <td>
                  <span className={`badge ${branch.status}`}>{branch.status === "active" ? "activa" : "oculta"}</span>
                </td>
                <td>
                  <form action={setBranchStatus.bind(null, merchantId, branch.id, branch.status === "active" ? "paused" : "active")}>
                    <button type="submit" className="secondary">
                      {branch.status === "active" ? "Ocultar" : "Mostrar"}
                    </button>
                  </form>
                  <ActionForm
                    action={deleteBranch.bind(null, merchantId, branch.id)}
                    confirm={`¿Eliminar la sucursal “${branch.name}”? Sus canjes pasados se cuentan como de la principal.`}
                    submitLabel="Eliminar"
                    inline
                  >
                    <input type="hidden" name="branch" value={branch.id} />
                  </ActionForm>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h4 style={{ margin: "16px 0 6px" }}>Agregar sucursal</h4>
      <ActionForm action={createBranch.bind(null, merchantId)} className="grid-form" submitLabel="Agregar sucursal" resetOnSuccess>
        <div className="field">
          <label>Nombre</label>
          <input type="text" name="name" required maxLength={80} placeholder="Costa del Este" />
        </div>
        <div className="field">
          <label>Dirección</label>
          <input type="text" name="address" maxLength={300} placeholder="Town Center, local 12" />
        </div>
        <div className="field" style={{ gridColumn: "1 / -1" }}>
          <label>Enlace de Google Maps</label>
          <input type="url" name="maps_url" maxLength={1000} placeholder="https://maps.app.goo.gl/…" />
        </div>
      </ActionForm>
    </div>
  );
}

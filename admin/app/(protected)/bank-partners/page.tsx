import { supabaseAdmin } from "@/lib/supabase-admin";
import { createBankPartner, updateBankPartnerStatus } from "./actions";

type BankPartner = { id: string; name: string; status: "active" | "paused" };

export default async function BankPartnersPage() {
  const supabase = supabaseAdmin();
  const { data: partners } = await supabase
    .from("bank_partners")
    .select("id, name, status")
    .order("name", { ascending: true })
    .returns<BankPartner[]>();

  return (
    <>
      <h1>Bancos patrocinadores</h1>
      <p className="text-dim">
        "Ahorro verificado" (B2) — un usuario se inscribe con uno de estos bancos usando un identificador opaco
        de cuenta (nunca el numero real) y pone una meta mensual. Ver "Reportes de banco" para subir los reportes
        de cumplimiento.
      </p>

      <div className="card">
        <h3>Nuevo banco</h3>
        <form action={createBankPartner} className="grid-form">
          <div className="field">
            <label>Nombre</label>
            <input type="text" name="name" required />
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
              <th>Estado</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {(partners ?? []).map((partner) => (
              <tr key={partner.id}>
                <td>{partner.name}</td>
                <td>
                  <span className={`badge ${partner.status}`}>{partner.status}</span>
                </td>
                <td>
                  <form action={updateBankPartnerStatus.bind(null, partner.id, partner.status === "active" ? "paused" : "active")}>
                    <button type="submit" className="secondary">
                      {partner.status === "active" ? "Pausar" : "Reactivar"}
                    </button>
                  </form>
                </td>
              </tr>
            ))}
            {(partners ?? []).length === 0 && (
              <tr>
                <td colSpan={3} className="text-dim">
                  Todavia no hay bancos patrocinadores.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </>
  );
}

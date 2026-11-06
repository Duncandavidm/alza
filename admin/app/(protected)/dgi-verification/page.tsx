import { supabaseAdmin } from "@/lib/supabase-admin";
import { setDgiVerificationEnabled, updateDgiRules } from "./actions";
import RunDgiVerificationButton from "./RunDgiVerificationButton";

type DgiReceiptRow = {
  id: string;
  cufe: string;
  ruc: string;
  status: string;
  confirmed_amount: number | null;
  payment_method: string | null;
  scanned_at: string;
  dgi_checked_at: string | null;
};

async function countReceipts(status: string): Promise<number> {
  const supabase = supabaseAdmin();
  const { count } = await supabase
    .from("dgi_receipts")
    .select("id", { count: "exact", head: true })
    .eq("status", status);
  return count ?? 0;
}

export default async function DgiVerificationPage() {
  const supabase = supabaseAdmin();

  const [{ data: config }, { data: rules }, pendiente, confirmada, expirada, { data: recent }] = await Promise.all([
    supabase
      .from("app_config")
      .select("key, value")
      .in("key", ["dgi_verification_enabled", "dgi_verification_expire_after_days"]),
    supabase.from("points_rules").select("key, value").eq("source", "factura"),
    countReceipts("pendiente"),
    countReceipts("confirmada"),
    countReceipts("expirada"),
    supabase
      .from("dgi_receipts")
      .select("id, cufe, ruc, status, confirmed_amount, payment_method, scanned_at, dgi_checked_at")
      .order("scanned_at", { ascending: false })
      .limit(50)
      .returns<DgiReceiptRow[]>(),
  ]);

  const configMap = Object.fromEntries((config ?? []).map((row) => [row.key, row.value]));
  const rulesMap = Object.fromEntries((rules ?? []).map((row) => [row.key, row.value]));

  const enabled = configMap.dgi_verification_enabled === true;
  const expireAfterDays = Number(configMap.dgi_verification_expire_after_days ?? 7);
  const pointsPerDollar = Number(rulesMap.points_per_dollar ?? 1);
  const dailyCap = Number(rulesMap.daily_cap_points_per_user ?? 300);

  return (
    <>
      <h1>Facturas que suman — verificacion DGI</h1>
      <p className="text-dim">
        El job verify-dgi-receipt corre todos los días a las 8:00 a. m. (hora de Panamá, pg_cron) y consulta cada factura pendiente directo contra
        dgi-fep.mef.gob.pa. Confirmada, acredita puntos de "factura" y, si la DGI reporta pago con tarjeta en un
        comercio aliado con oferta activa, tambien el bono de "tarjeta" — sin vincular ninguna tarjeta.
      </p>

      <div className="card">
        <h3>Estado</h3>
        <p>
          Verificacion automatica: <span className={`badge ${enabled ? "active" : "paused"}`}>{enabled ? "activa" : "apagada"}</span>
        </p>
        <p className="text-dim" style={{ marginBottom: 10 }}>
          {enabled
            ? "El cron awards puntos de verdad. Apagar esto detiene nuevos puntos, pero no toca los ya otorgados."
            : "El cron corre pero no hace nada (modo seguro) hasta que esto se active."}
        </p>
        <form action={setDgiVerificationEnabled.bind(null, !enabled)}>
          <button type="submit" className={enabled ? "danger" : undefined}>
            {enabled ? "Apagar verificacion" : "Activar verificacion"}
          </button>
        </form>
      </div>

      <div className="card">
        <h3>Reglas</h3>
        <form action={updateDgiRules} className="grid-form">
          <div className="field">
            <label>Puntos por dolar confirmado</label>
            <input type="number" name="points_per_dollar" defaultValue={pointsPerDollar} min={0} step="0.1" required />
          </div>
          <div className="field">
            <label>Tope diario de puntos por usuario (factura)</label>
            <input type="number" name="daily_cap_points_per_user" defaultValue={dailyCap} min={0} step="1" required />
          </div>
          <div className="field">
            <label>Dias antes de expirar una factura sin confirmar</label>
            <input type="number" name="expire_after_days" defaultValue={expireAfterDays} min={1} step="1" required />
          </div>
          <div className="field" style={{ alignSelf: "end" }}>
            <button type="submit">Guardar</button>
          </div>
        </form>
      </div>

      <div className="card">
        <h3>Procesar pendientes ahora</h3>
        <p className="text-dim">
          Dispara verify-dgi-receipt de una vez, sin esperar la proxima corrida del cron. Util para probar antes de
          activar la verificacion.
        </p>
        <RunDgiVerificationButton />
      </div>

      <div className="grid-form">
        <div className="card">
          <div className="text-dim">Pendientes</div>
          <div style={{ fontSize: 28, fontWeight: 700 }}>{pendiente}</div>
        </div>
        <div className="card">
          <div className="text-dim">Confirmadas</div>
          <div style={{ fontSize: 28, fontWeight: 700, color: "var(--success)" }}>{confirmada}</div>
        </div>
        <div className="card">
          <div className="text-dim">Expiradas</div>
          <div style={{ fontSize: 28, fontWeight: 700 }}>{expirada}</div>
        </div>
      </div>

      <div className="card">
        <h3>Ultimas facturas escaneadas</h3>
        <table>
          <thead>
            <tr>
              <th>Escaneada</th>
              <th>RUC</th>
              <th>CUFE</th>
              <th>Estado</th>
              <th>Monto confirmado</th>
              <th>Forma de pago</th>
            </tr>
          </thead>
          <tbody>
            {(recent ?? []).map((row) => (
              <tr key={row.id}>
                <td>{new Date(row.scanned_at).toLocaleString("es-PA")}</td>
                <td>{row.ruc}</td>
                <td className="text-dim">{row.cufe.slice(0, 12)}...</td>
                <td>
                  <span className={`badge ${row.status}`}>{row.status}</span>
                </td>
                <td>{row.confirmed_amount !== null ? `$${Number(row.confirmed_amount).toFixed(2)}` : "—"}</td>
                <td className="text-dim">{row.payment_method ?? "—"}</td>
              </tr>
            ))}
            {(recent ?? []).length === 0 && (
              <tr>
                <td colSpan={6} className="text-dim">
                  Sin facturas escaneadas todavia.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </>
  );
}

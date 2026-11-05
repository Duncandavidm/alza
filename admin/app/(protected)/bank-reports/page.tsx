import { supabaseAdmin } from "@/lib/supabase-admin";
import UploadBankReportForm from "./UploadBankReportForm";
import RunBankReconciliationForm from "./RunBankReconciliationForm";

type BankPartner = { id: string; name: string };
type BankReportRow = {
  id: string;
  external_account_ref: string;
  period_month: string;
  avg_balance: number;
  match_status: string;
  match_note: string | null;
  points_awarded: number | null;
};

export default async function BankReportsPage() {
  const supabase = supabaseAdmin();

  const { data: partners } = await supabase
    .from("bank_partners")
    .select("id, name")
    .eq("status", "active")
    .order("name", { ascending: true })
    .returns<BankPartner[]>();

  const { data: recent } = await supabase
    .from("savings_bank_reports")
    .select("id, external_account_ref, period_month, avg_balance, match_status, match_note, points_awarded")
    .order("provided_at", { ascending: false })
    .limit(50)
    .returns<BankReportRow[]>();

  return (
    <>
      <h1>Reportes de banco (ahorro verificado)</h1>
      <p className="text-dim">
        Sube el reporte mensual del banco patrocinador — saldo PROMEDIO del mes por identificador de cuenta
        (nunca el numero real). Se cruza contra las inscripciones activas y decide si la meta del mes se cumplio.
      </p>

      <div className="card">
        <h3>Subir reporte</h3>
        {(partners ?? []).length === 0 ? (
          <p className="text-dim">Crea un banco patrocinador activo primero.</p>
        ) : (
          <UploadBankReportForm partners={partners ?? []} />
        )}
        <p className="text-dim" style={{ marginTop: 10 }}>
          Columnas del CSV: <code>external_account_ref, period_month, avg_balance</code>. <code>period_month</code>:
          primer dia del mes que se reporta (yyyy-MM-dd).
        </p>
      </div>

      <div className="card">
        <h3>Procesar</h3>
        {(partners ?? []).length === 0 ? (
          <p className="text-dim">Crea un banco patrocinador activo primero.</p>
        ) : (
          <RunBankReconciliationForm partners={partners ?? []} />
        )}
      </div>

      <div className="card">
        <h3>Ultimos reportes</h3>
        <table>
          <thead>
            <tr>
              <th>Periodo</th>
              <th>Cuenta</th>
              <th>Saldo promedio</th>
              <th>Estado</th>
              <th>Nota</th>
              <th>Puntos</th>
            </tr>
          </thead>
          <tbody>
            {(recent ?? []).map((row) => (
              <tr key={row.id}>
                <td>{row.period_month}</td>
                <td>{row.external_account_ref}</td>
                <td>${Number(row.avg_balance).toFixed(2)}</td>
                <td>
                  <span className={`badge ${row.match_status}`}>{row.match_status}</span>
                </td>
                <td className="text-dim">{row.match_note ?? "—"}</td>
                <td>{row.points_awarded ?? "—"}</td>
              </tr>
            ))}
            {(recent ?? []).length === 0 && (
              <tr>
                <td colSpan={6} className="text-dim">
                  Sin reportes todavia.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </>
  );
}

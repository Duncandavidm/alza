import { supabaseAdmin } from "@/lib/supabase-admin";
import { approveIncome, rejectIncome } from "./actions";

export const dynamic = "force-dynamic";

type Verification = {
  id: string;
  user_id: string;
  status: string;
  document_kind: string;
  document_path: string | null;
  ai_name: string | null;
  ai_monthly_income: number | null;
  ai_summary: string | null;
  approved_amount: number | null;
  note: string | null;
  created_at: string;
  reviewed_at: string | null;
};

const KINDS: Record<string, string> = {
  talonario: "Talonario / comprobante de pago",
  carta_trabajo: "Carta de trabajo",
  css: "Constancia de la CSS",
  estado_cuenta: "Estado de cuenta",
  declaracion_renta: "Declaración de renta",
  otro: "Otro documento",
};

const money = (value: number | null | undefined) =>
  value == null ? "—" : "$" + Number(value).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export default async function IncomeVerificationPage() {
  const supabase = supabaseAdmin();
  const { data } = await supabase
    .from("income_verifications")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(200);
  const rows = (data ?? []) as Verification[];
  const userIds = [...new Set(rows.map((r) => r.user_id))];
  const { data: profiles } = userIds.length
    ? await supabase.from("profiles").select("id, full_name, country").in("id", userIds)
    : { data: [] };
  const profileById = new Map((profiles ?? []).map((p: { id: string; full_name: string | null; country: string }) => [p.id, p]));

  const pending = rows.filter((r) => r.status === "pendiente");
  const done = rows.filter((r) => r.status !== "pendiente");
  const links = new Map<string, string>();
  for (const row of pending) {
    if (!row.document_path) continue;
    const { data: signed } = await supabase.storage.from("income-docs").createSignedUrl(row.document_path, 600);
    if (signed?.signedUrl) links.set(row.id, signed.signedUrl);
  }

  return (
    <>
      <h1>Verificación de ingresos</h1>
      <p className="text-dim">
        Para el cashback, los ingresos anotados cuentan hasta $3,000 al mes sin verificar. Quien gana más sube un
        documento desde la app. La IA sugiere el nombre y el monto; tú confirmas. Al aprobar, cuenta el monto aprobado
        durante 6 meses. El documento se borra al aprobar o rechazar: solo queda el monto.
      </p>

      <h2>Pendientes ({pending.length})</h2>
      {pending.length === 0 && <p className="text-dim">No hay documentos por revisar.</p>}
      {pending.map((row) => {
        const profile = profileById.get(row.user_id);
        return (
          <div className="card" key={row.id}>
            <h3>{profile?.full_name ?? "Sin nombre"} · {KINDS[row.document_kind] ?? row.document_kind}</h3>
            <p className="text-dim">
              Enviado el {new Date(row.created_at).toLocaleString("es-PA", { timeZone: "America/Panama" })} ·{" "}
              <a href={`/clientes/${row.user_id}`}>ver cliente</a>
              {links.get(row.id) && <> · <a href={links.get(row.id)} target="_blank" rel="noopener noreferrer">Abrir documento (10 min)</a></>}
            </p>
            <p>
              <b>Lectura de la IA:</b> {row.ai_summary ?? "Sin lectura (la persona no permitió IA o no se pudo leer): revísalo a mano."}
            </p>
            <p className="text-dim">
              Nombre en el documento: {row.ai_name ?? "—"} · Ingreso mensual sugerido: {money(row.ai_monthly_income)}
              {row.ai_name && profile?.full_name && !row.ai_name.toLowerCase().includes(profile.full_name.toLowerCase().split(" ")[0])
                ? " · ⚠️ El nombre no parece coincidir con el de la cuenta" : ""}
            </p>
            <form style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
              <input name="amount" defaultValue={row.ai_monthly_income ?? ""} placeholder="Ingreso mensual aprobado" inputMode="decimal" style={{ width: 200 }} />
              <input name="note" placeholder="Nota para la persona (opcional)" style={{ flex: 1, minWidth: 200 }} />
              <button formAction={approveIncome.bind(null, row.id)}>Aprobar</button>
              <button className="danger" formAction={rejectIncome.bind(null, row.id)}>Rechazar</button>
            </form>
          </div>
        );
      })}

      <h2>Revisadas</h2>
      {done.length === 0 && <p className="text-dim">Todavía no hay solicitudes revisadas.</p>}
      {done.length > 0 && (
        <table>
          <thead>
            <tr><th>Cliente</th><th>Documento</th><th>Resultado</th><th>Monto</th><th>Nota</th><th>Fecha</th></tr>
          </thead>
          <tbody>
            {done.map((row) => (
              <tr key={row.id}>
                <td>{profileById.get(row.user_id)?.full_name ?? row.user_id.slice(0, 8)}</td>
                <td>{KINDS[row.document_kind] ?? row.document_kind}</td>
                <td><span className={`badge ${row.status === "aprobada" ? "active" : "paused"}`}>{row.status}</span></td>
                <td>{money(row.approved_amount)}</td>
                <td>{row.note ?? ""}</td>
                <td>{row.reviewed_at ? new Date(row.reviewed_at).toLocaleDateString("es-PA") : ""}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </>
  );
}

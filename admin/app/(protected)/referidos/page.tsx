import Link from "next/link";
import { supabaseAdmin } from "@/lib/supabase-admin";
import ActionForm from "@/components/ActionForm";
import { centsToDollarInput, formatCashback, formatDateTime } from "@/lib/format";
import { updateReferralRewards } from "./actions";

export const dynamic = "force-dynamic";

type ReferralRow = {
  id: string;
  referrer_id: string;
  referee_id: string;
  status: string;
  created_at: string;
  rewarded_at: string | null;
};

const STATUS_LABEL: Record<string, string> = {
  pendiente: "Esperando su primera factura",
  premiado: "Pagado",
  sin_premio: "Sin premio (llegó al tope del mes)",
};

/// "Invita amigos y gana cashback": cuanto se gana, el tope por mes y
/// como va el programa. La app lee los montos del servidor.
export default async function ReferralsPage() {
  const supabase = supabaseAdmin();
  const monthStart = new Date();
  monthStart.setUTCDate(1);
  monthStart.setUTCHours(5, 0, 0, 0); // medianoche de Panama

  const [{ data: config }, { data: referrals }, { data: paid }] = await Promise.all([
    supabase
      .from("app_config")
      .select("key, value")
      .in("key", ["referral_cashback_referrer_cents", "referral_cashback_referee_cents", "referral_monthly_cap"]),
    supabase
      .from("referrals")
      .select("id, referrer_id, referee_id, status, created_at, rewarded_at")
      .order("created_at", { ascending: false })
      .limit(500)
      .returns<ReferralRow[]>(),
    supabase.from("points_ledger").select("points, created_at").eq("source", "referido").limit(10000)
      .returns<{ points: number; created_at: string }[]>(),
  ]);

  const values = Object.fromEntries((config ?? []).map((row) => [row.key, Number(row.value)]));
  const referrerCents = values.referral_cashback_referrer_cents ?? 100;
  const refereeCents = values.referral_cashback_referee_cents ?? 50;
  const cap = values.referral_monthly_cap ?? 10;

  const rows = referrals ?? [];
  const count = (status: string) => rows.filter((row) => row.status === status).length;
  const paidTotal = (paid ?? []).reduce((sum, row) => sum + Number(row.points), 0);
  const paidMonth = (paid ?? [])
    .filter((row) => new Date(row.created_at) >= monthStart)
    .reduce((sum, row) => sum + Number(row.points), 0);

  // Correos de las ultimas 20 invitaciones (solo para el panel).
  const recent = rows.slice(0, 20);
  const ids = [...new Set(recent.flatMap((row) => [row.referrer_id, row.referee_id]))];
  const emails = new Map<string, string>();
  await Promise.all(ids.map(async (id) => {
    const { data } = await supabase.auth.admin.getUserById(id);
    if (data?.user?.email) emails.set(id, data.user.email);
  }));
  const who = (id: string) => (
    <Link href={`/clientes/${id}`}>{emails.get(id) ?? "Cuenta borrada"}</Link>
  );

  return (
    <>
      <h1>Invita amigos y gana cashback</h1>
      <p className="text-dim">
        Cada persona tiene un código para invitar. Cuando su amigo se registra con ese código y escanea su primera factura
        fiscal (confirmada por la DGI), los dos ganan cashback. Lo que cambies aquí lo ve la app al momento, sin
        actualizarla, y aplica a los amigos que cumplan desde ahora.
      </p>

      <div className="card">
        <h3>Cuánto se gana</h3>
        <ActionForm action={updateReferralRewards} className="grid-form" submitLabel="Guardar">
          <div className="field">
            <label>Quien invita gana (US$)</label>
            <input type="text" inputMode="decimal" name="referrer" defaultValue={centsToDollarInput(referrerCents)} required />
            <span className="text-dim">Hoy: {formatCashback(referrerCents)} por cada amigo.</span>
          </div>
          <div className="field">
            <label>El amigo invitado gana (US$)</label>
            <input type="text" inputMode="decimal" name="referee" defaultValue={centsToDollarInput(refereeCents)} required />
            <span className="text-dim">Hoy: {formatCashback(refereeCents)} de bienvenida. Pon 0 para no darle nada.</span>
          </div>
          <div className="field">
            <label>Tope de amigos premiados por persona (cada 30 días)</label>
            <input type="number" name="cap" min={1} max={100} step={1} defaultValue={cap} required />
            <span className="text-dim">Evita abusos: pasado el tope, el amigo igual recibe lo suyo pero quien invita no.</span>
          </div>
        </ActionForm>
        <p className="text-dim" style={{ marginTop: 10 }}>
          Ejemplo: con estos montos, 100 amigos nuevos te cuestan hasta {formatCashback((referrerCents + refereeCents) * 100)} en
          cashback (se paga cuando lo canjean en los comercios aliados).
        </p>
      </div>

      <div className="grid-form">
        <div className="card">
          <div className="text-dim">Invitados en total</div>
          <div style={{ fontSize: 28, fontWeight: 700 }}>{rows.length}</div>
        </div>
        <div className="card">
          <div className="text-dim">Esperando su primera factura</div>
          <div style={{ fontSize: 28, fontWeight: 700 }}>{count("pendiente")}</div>
        </div>
        <div className="card">
          <div className="text-dim">Pagados</div>
          <div style={{ fontSize: 28, fontWeight: 700, color: "var(--success)" }}>{count("premiado")}</div>
        </div>
        <div className="card">
          <div className="text-dim">Cashback pagado (este mes / total)</div>
          <div style={{ fontSize: 28, fontWeight: 700 }}>{formatCashback(paidMonth)} / {formatCashback(paidTotal)}</div>
        </div>
      </div>

      <div className="card">
        <h3>Últimas invitaciones</h3>
        <table>
          <thead>
            <tr>
              <th>Fecha</th>
              <th>Invitó</th>
              <th>Amigo</th>
              <th>Estado</th>
              <th>Pagado</th>
            </tr>
          </thead>
          <tbody>
            {recent.map((row) => (
              <tr key={row.id}>
                <td>{formatDateTime(row.created_at)}</td>
                <td>{who(row.referrer_id)}</td>
                <td>{who(row.referee_id)}</td>
                <td><span className={`badge ${row.status === "premiado" ? "active" : "paused"}`}>{STATUS_LABEL[row.status] ?? row.status}</span></td>
                <td className="text-dim">{formatDateTime(row.rewarded_at)}</td>
              </tr>
            ))}
            {recent.length === 0 && (
              <tr>
                <td colSpan={5} className="text-dim">Todavía nadie ha invitado a un amigo.</td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </>
  );
}

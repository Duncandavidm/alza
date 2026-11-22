import ActionForm from "@/components/ActionForm";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { formatDate, formatInt } from "@/lib/format";
import { createMerchantChallenge, setMerchantChallengeStatus } from "./challenge-actions";

type ChallengeRow = {
  id: string;
  title: string;
  required_receipts: number;
  starts_at: string;
  ends_at: string | null;
  max_winners: number | null;
  expires_days: number;
  status: "active" | "paused";
  reward_items: { name: string } | { name: string }[] | null;
};

function itemName(row: ChallengeRow): string {
  const item = Array.isArray(row.reward_items) ? row.reward_items[0] : row.reward_items;
  return item?.name ?? "Premio";
}

/// Retos del comercio: "Escanea 3 facturas de este comercio y gana un
/// premio". Cuentan las facturas confirmadas por la DGI con el RUC del
/// comercio; el premio llega solo, con aviso, al completar el reto.
export default async function ChallengesCard({ merchantId, merchantRuc }: { merchantId: string; merchantRuc: string | null }) {
  const supabase = supabaseAdmin();
  const { data: challenges, error } = await supabase
    .from("merchant_challenges")
    .select("id, title, required_receipts, starts_at, ends_at, max_winners, expires_days, status, reward_items(name)")
    .eq("merchant_id", merchantId)
    .order("created_at", { ascending: false })
    .returns<ChallengeRow[]>();

  if (error) {
    return (
      <div className="card">
        <h3>Retos de facturas</h3>
        <p className="error" style={{ margin: 0 }}>
          Falta aplicar la migración 0083 (retos por comercio) en Supabase.
        </p>
      </div>
    );
  }

  const ids = (challenges ?? []).map((c) => c.id);
  const { data: grants } = ids.length
    ? await supabase.from("merchant_challenge_grants").select("challenge_id").in("challenge_id", ids)
    : { data: [] as { challenge_id: string }[] };
  const winners = new Map<string, number>();
  for (const grant of grants ?? []) winners.set(grant.challenge_id, (winners.get(grant.challenge_id) ?? 0) + 1);

  // Participantes: clientes con al menos una factura confirmada del
  // comercio dentro del periodo de cada reto.
  const participants = new Map<string, number>();
  if (merchantRuc && ids.length) {
    const since = (challenges ?? []).reduce((min, c) => (c.starts_at < min ? c.starts_at : min), new Date().toISOString());
    const { data: receipts } = await supabase
      .from("dgi_receipts")
      .select("user_id, scanned_at")
      .eq("ruc", merchantRuc)
      .eq("status", "confirmada")
      .gte("scanned_at", since)
      .limit(20000)
      .returns<{ user_id: string; scanned_at: string }[]>();
    for (const challenge of challenges ?? []) {
      const users = new Set(
        (receipts ?? [])
          .filter((r) => r.scanned_at >= challenge.starts_at && (!challenge.ends_at || r.scanned_at <= challenge.ends_at))
          .map((r) => r.user_id)
      );
      participants.set(challenge.id, users.size);
    }
  }

  const now = new Date().toISOString();

  return (
    <div className="card">
      <h3>Retos de facturas</h3>
      <p className="text-dim">
        “Escanea 3 facturas de este comercio y gana un premio”. En la app (1.0.5) cada cliente ve su avance; cuentan las
        facturas que la DGI confirma con el RUC del comercio. El premio se entrega solo, con aviso, al completar el reto.
      </p>
      {!merchantRuc && <p className="error">Este comercio no tiene RUC en su ficha: agrégalo para poder crear retos.</p>}

      {(challenges ?? []).length > 0 && (
        <div className="table-scroll" style={{ marginBottom: 16 }}>
          <table>
            <thead>
              <tr>
                <th>Reto</th>
                <th>Facturas</th>
                <th>Premio</th>
                <th>Vigencia</th>
                <th>Participan</th>
                <th>Ganadores</th>
                <th>Estado</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {(challenges ?? []).map((challenge) => {
                const ended = Boolean(challenge.ends_at && challenge.ends_at < now);
                const won = winners.get(challenge.id) ?? 0;
                return (
                  <tr key={challenge.id}>
                    <td>{challenge.title}</td>
                    <td>{challenge.required_receipts}</td>
                    <td>{itemName(challenge)}</td>
                    <td>
                      {formatDate(challenge.starts_at)} – {challenge.ends_at ? formatDate(challenge.ends_at) : "sin fin"}
                    </td>
                    <td>{formatInt(participants.get(challenge.id) ?? 0)}</td>
                    <td>
                      {formatInt(won)}
                      {challenge.max_winners ? ` de ${formatInt(challenge.max_winners)}` : ""}
                    </td>
                    <td>
                      <span className={`badge ${ended ? "paused" : challenge.status}`}>
                        {ended ? "Terminado" : challenge.status === "active" ? "Activo" : "Pausado"}
                      </span>
                    </td>
                    <td>
                      {!ended && (
                        <form
                          action={setMerchantChallengeStatus.bind(
                            null,
                            merchantId,
                            challenge.id,
                            challenge.status === "active" ? "paused" : "active"
                          )}
                        >
                          <button type="submit" className="secondary">
                            {challenge.status === "active" ? "Pausar" : "Activar"}
                          </button>
                        </form>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {merchantRuc && (
        <ActionForm action={createMerchantChallenge.bind(null, merchantId)} className="grid-form" resetOnSuccess submitLabel="Crear reto">
          <div className="field">
            <label>Facturas necesarias</label>
            <input type="number" name="required_receipts" min={1} max={50} step={1} defaultValue={3} required />
          </div>
          <div className="field">
            <label>Premio</label>
            <input type="text" name="prize" maxLength={120} placeholder="Café gratis" required />
          </div>
          <div className="field">
            <label>Valor del premio (US$, opcional)</label>
            <input type="text" name="value" inputMode="decimal" placeholder="3.50" />
          </div>
          <div className="field">
            <label>Termina el (opcional)</label>
            <input type="date" name="ends_on" />
          </div>
          <div className="field">
            <label>Máximo de ganadores (opcional)</label>
            <input type="number" name="max_winners" min={1} step={1} placeholder="Sin límite" />
          </div>
          <div className="field">
            <label>Días para usar el premio</label>
            <input type="number" name="expires_days" min={1} max={365} step={1} defaultValue={30} />
          </div>
          <div className="field">
            <label>Título (opcional)</label>
            <input type="text" name="title" maxLength={120} placeholder="Escanea 3 facturas y gana un café gratis" />
          </div>
          <div className="field">
            <label>Condiciones (opcional)</label>
            <textarea name="conditions" maxLength={500} rows={2} placeholder="Válido en todas las sucursales. No acumulable." />
          </div>
        </ActionForm>
      )}
    </div>
  );
}

import Link from "next/link";
import { supabaseAdmin } from "@/lib/supabase-admin";
import ActionForm from "@/components/ActionForm";
import { formatInt } from "@/lib/format";
import { HABIT_RULE_TYPES, habitRuleLabel } from "@/lib/habit-coupons";
import { createHabitCoupon, setHabitCouponStatus } from "./actions";
import CouponTabs from "@/components/CouponTabs";
import CouponSettlement from "@/components/CouponSettlement";

export const dynamic = "force-dynamic";

type Rule = {
  id: string;
  name: string;
  rule_type: string;
  threshold: number;
  min_logged_days: number;
  max_coupons: number | null;
  expires_days: number;
  status: "active" | "paused";
  created_at: string;
  reward_items: { name: string; points_cost: number; partner_merchants: { name: string } | null } | null;
};

/// Cupones por buenos habitos: MonAvi le compra el cupon al comercio y se
/// lo regala a quien cumple una regla (ahorro, metas, presupuestos...).
export default async function HabitCouponsPage() {
  const supabase = supabaseAdmin();
  const [{ data: rules }, { data: merchants }, { data: grants }] = await Promise.all([
    supabase
      .from("habit_coupon_rules")
      .select("id, name, rule_type, threshold, min_logged_days, max_coupons, expires_days, status, created_at, reward_items(name, points_cost, partner_merchants(name))")
      .order("created_at", { ascending: false })
      .returns<Rule[]>(),
    supabase
      .from("partner_merchants")
      .select("id, name, status")
      .order("name")
      .returns<{ id: string; name: string; status: string }[]>(),
    supabase
      .from("habit_coupon_grants")
      .select("rule_id, reward_redemptions(status)")
      .returns<{ rule_id: string; reward_redemptions: { status: string } | null }[]>(),
  ]);

  const issued = new Map<string, number>();
  const used = new Map<string, number>();
  for (const grant of grants ?? []) {
    issued.set(grant.rule_id, (issued.get(grant.rule_id) ?? 0) + 1);
    if (grant.reward_redemptions?.status === "entregado") used.set(grant.rule_id, (used.get(grant.rule_id) ?? 0) + 1);
  }

  return (
    <>
      <h1>Cupones</h1>
      <CouponTabs active="habitos" />
      <p className="text-dim">
        Las mismas reglas de buenos hábitos que antes daban puntos ahora dan cupones. Tú creas el cupón (por ejemplo <em>$20 en Bungla</em>), eliges la
        regla para ganarlo (o lo das a todos, sin reglas) y MonAvi se lo entrega solo a quien la cumple, con un aviso en su teléfono. El cliente lo usa en
        caja como cualquier canje y abajo ves cuánto le debes a cada comercio. La salud financiera de cada persona está en{" "}
        <Link href="/clientes">Clientes</Link>.
      </p>

      <div className="card">
        <h3>Nuevo cupón automático</h3>
        <ActionForm action={createHabitCoupon} className="grid-form" submitLabel="Crear cupón" resetOnSuccess>
          <div className="field">
            <label>Comercio</label>
            <select name="merchant_id" required defaultValue="">
              <option value="" disabled>
                Elige el comercio
              </option>
              {(merchants ?? []).map((merchant) => (
                <option key={merchant.id} value={merchant.id}>
                  {merchant.name}
                  {merchant.status === "active" ? "" : " (oculto)"}
                </option>
              ))}
            </select>
          </div>
          <div className="field">
            <label>Valor del cupón (US$)</label>
            <input type="number" name="value" required min={1} step={0.01} inputMode="decimal" placeholder="20" />
          </div>
          <div className="field">
            <label>Nombre del cupón (opcional)</label>
            <input type="text" name="coupon_name" maxLength={120} placeholder="Cupón de $20" />
          </div>
          <div className="field">
            <label>Regla para ganarlo</label>
            <select name="rule_type" defaultValue="ahorro_ingresos">
              {HABIT_RULE_TYPES.map((type) => (
                <option key={type.value} value={type.value}>
                  {type.label}
                </option>
              ))}
            </select>
          </div>
          <div className="field">
            <label>Mínimo de la regla</label>
            <input type="number" name="threshold" min={0} step={0.01} placeholder="20 (vacío si es para todos)" />
          </div>
          <div className="field">
            <label>Días anotados mínimos en el mes</label>
            <input type="number" name="min_logged_days" min={0} max={31} step={1} defaultValue={15} />
          </div>
          <div className="field">
            <label>Máximo de cupones (vacío = sin límite)</label>
            <input type="number" name="max_coupons" min={1} step={1} placeholder="100" />
          </div>
          <div className="field">
            <label>Días para usarlo</label>
            <input type="number" name="expires_days" min={1} max={365} step={1} defaultValue={30} />
          </div>
          <div className="field" style={{ gridColumn: "1 / -1" }}>
            <label>Condiciones en caja (opcional)</label>
            <input type="text" name="conditions" maxLength={500} placeholder="En compras desde $40. No acumulable." />
          </div>
          <div className="field" style={{ gridColumn: "1 / -1" }}>
            <label>Mensaje para el cliente (opcional)</label>
            <input type="text" name="message" maxLength={300} placeholder="¡Felicidades! Ahorraste el 20% de tus ingresos este mes." />
          </div>
          <div className="field" style={{ gridColumn: "1 / -1" }}>
            <label>Imagen del cupón (opcional, sale en el aviso y en la app)</label>
            <input type="file" name="photo" accept="image/jpeg,image/png,image/webp" />
          </div>
        </ActionForm>
        <details style={{ marginTop: 12 }}>
          <summary>Cómo funciona cada regla</summary>
          <ul>
            {HABIT_RULE_TYPES.map((type) => (
              <li key={type.value}>
                <strong>{type.label}</strong> ({type.threshold}): {type.help}
              </li>
            ))}
          </ul>
          <p className="text-dim">
            En &quot;Para todos&quot; no se miran ni el mínimo ni los días anotados: solo el máximo de cupones.
            &quot;Días anotados mínimos&quot; evita que alguien gane dejando de anotar sus gastos: solo cuenta quien usa la app
            de verdad. Cada persona gana el cupón una vez por mes (una vez por semana en la regla semanal, una vez por
            meta en la de metas). Para darle un cupón a alguien en particular, usa &quot;Regalar cupones&quot;.
          </p>
        </details>
      </div>

      <div className="card table-scroll">
        <h3>Cupones automáticos</h3>
        <table>
          <thead>
            <tr>
              <th>Cupón</th>
              <th>Regla</th>
              <th>Entregados</th>
              <th>Usados en caja</th>
              <th>Estado</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {(rules ?? []).map((rule) => (
              <tr key={rule.id}>
                <td>
                  {rule.reward_items?.name ?? rule.name}
                  <div className="text-dim">
                    {rule.reward_items?.partner_merchants?.name ?? "—"} · vence a los {rule.expires_days} días
                  </div>
                </td>
                <td>
                  {habitRuleLabel(rule.rule_type)}
                  <div className="text-dim">
                    Mínimo {rule.threshold} · {rule.min_logged_days} días anotados
                  </div>
                </td>
                <td>
                  {formatInt(issued.get(rule.id) ?? 0)}
                  {rule.max_coupons ? ` de ${formatInt(rule.max_coupons)}` : ""}
                </td>
                <td>{formatInt(used.get(rule.id) ?? 0)}</td>
                <td>
                  <span className={`badge ${rule.status}`}>{rule.status === "active" ? "activo" : "pausado"}</span>
                </td>
                <td>
                  <form action={setHabitCouponStatus.bind(null, rule.id, rule.status === "active" ? "paused" : "active")}>
                    <button type="submit" className="secondary">
                      {rule.status === "active" ? "Pausar" : "Reactivar"}
                    </button>
                  </form>
                </td>
              </tr>
            ))}
            {(rules ?? []).length === 0 && (
              <tr>
                <td colSpan={6} className="text-dim">
                  Todavía no hay cupones. Crea el primero arriba.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <CouponSettlement />
    </>
  );
}

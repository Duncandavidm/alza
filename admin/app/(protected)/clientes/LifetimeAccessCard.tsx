import Link from "next/link";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { LIFETIME_PRODUCT_ID } from "@/lib/customer-accounts";
import { grantLifetimeByEmail } from "./actions";

/// Acceso Pro de por vida (gratis, sin vencimiento): darlo por correo y
/// ver quien lo tiene. Antes solo estaba dentro de la ficha de cada cliente.
export default async function LifetimeAccessCard() {
  const supabase = supabaseAdmin();
  const { data: subs } = await supabase
    .from("subscriptions")
    .select("user_id")
    .eq("product_id", LIFETIME_PRODUCT_ID)
    .eq("status", "active")
    .limit(50);

  const members = await Promise.all(
    (subs ?? []).map(async (sub: { user_id: string }) => {
      const { data } = await supabase.auth.admin.getUserById(sub.user_id);
      return { id: sub.user_id, email: data?.user?.email ?? "Cuenta sin correo" };
    })
  );

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>⭐ Acceso Pro de por vida</h3>
      <p className="text-dim">
        MonAvi Pro gratis y sin vencimiento (tu equipo, aliados, ganadores de un concurso). No es una compra de Apple y se
        puede quitar cuando quieras desde la ficha del cliente. La persona primero debe crear su cuenta en la app.
      </p>
      <form action={grantLifetimeByEmail} className="inline-actions">
        <input
          type="email"
          name="email"
          required
          placeholder="Correo con el que se registró en MonAvi"
          style={{ flex: "1 1 280px" }}
          aria-label="Correo del cliente"
        />
        <button type="submit">Dar acceso de por vida</button>
      </form>
      <p className="text-dim" style={{ marginBottom: 6 }}>
        {members.length === 0 ? "Todavía nadie tiene acceso de por vida." : `Lo tienen ${members.length}:`}
      </p>
      {members.length > 0 && (
        <div className="inline-actions" style={{ gap: 8 }}>
          {members.map((member) => (
            <Link key={member.id} href={`/clientes/${member.id}`} className="badge active">
              {member.email}
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}

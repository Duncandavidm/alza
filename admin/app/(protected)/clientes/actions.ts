"use server";

import { redirect } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { requireAdminSession } from "@/lib/admin-session";
import { setLifetimeAccess } from "./[id]/actions";

function backToList(key: "msg" | "err", text: string): never {
  redirect(`/clientes?${key}=${encodeURIComponent(text)}`);
}

/// "Dar Pro de por vida" desde la lista: busca la cuenta por su correo y
/// le da el acceso (misma logica que en la ficha del cliente, que es a
/// donde se llega al terminar). La persona primero debe tener su cuenta
/// creada en la app.
export async function grantLifetimeByEmail(formData: FormData) {
  await requireAdminSession();
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 200) {
    backToList("err", "Escribe un correo válido.");
  }

  const { data, error } = await supabaseAdmin().rpc("admin_customers", { p_search: email, p_limit: 20, p_offset: 0 });
  if (error) backToList("err", `No se pudo buscar la cuenta: ${error.message}`);
  const rows = ((data ?? {}) as { rows?: { id: string; email: string | null }[] }).rows ?? [];
  const match = rows.find((row) => (row.email ?? "").toLowerCase() === email);
  if (!match) {
    backToList("err", `No hay ninguna cuenta con ${email}. La persona primero debe descargar MonAvi y crear su cuenta con ese correo.`);
  }

  const form = new FormData();
  form.set("id", match.id);
  form.set("grant", "1");
  await setLifetimeAccess(form);
}

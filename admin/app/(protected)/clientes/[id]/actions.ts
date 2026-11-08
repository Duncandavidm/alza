"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { requireAdminSession } from "@/lib/admin-session";
import { parseUuid } from "@/lib/push";
import { SUSPEND_BAN_DURATION, isProtectedEmail } from "@/lib/customer-accounts";

function back(id: string, key: "msg" | "err", text: string): never {
  redirect(`/clientes/${id}?${key}=${encodeURIComponent(text)}`);
}

async function loadUser(rawId: unknown) {
  await requireAdminSession();
  const id = parseUuid(rawId);
  if (!id) redirect(`/clientes?err=${encodeURIComponent("Cliente inválido.")}`);
  const { data, error } = await supabaseAdmin().auth.admin.getUserById(id);
  if (error || !data?.user) back(id, "err", `No se encontró la cuenta: ${error?.message ?? "no existe"}`);
  return { id, user: data.user };
}

/// Suspende (suspend=1) o reactiva (suspend=0) la cuenta. Un usuario con
/// ban no puede iniciar sesion ni renovar su sesion.
export async function setCustomerSuspended(formData: FormData) {
  const { id, user } = await loadUser(formData.get("id"));
  const suspend = formData.get("suspend") === "1";
  if (isProtectedEmail(user.email)) {
    back(id, "err", "Esta es una cuenta protegida (demo / revisión de Apple): no se puede suspender ni eliminar desde el panel.");
  }
  const { error } = await supabaseAdmin().auth.admin.updateUserById(id, {
    ban_duration: suspend ? SUSPEND_BAN_DURATION : "none",
  });
  if (error) back(id, "err", `No se pudo ${suspend ? "suspender" : "reactivar"} la cuenta: ${error.message}`);
  revalidatePath("/clientes");
  revalidatePath(`/clientes/${id}`);
  back(id, "msg", suspend ? "Cuenta suspendida: ya no puede iniciar sesión." : "Cuenta reactivada.");
}

/// Borra la cuenta para siempre. Exige que el admin escriba el correo
/// exacto; los datos de la app se borran por ON DELETE CASCADE.
export async function deleteCustomer(formData: FormData) {
  const { id, user } = await loadUser(formData.get("id"));
  if (isProtectedEmail(user.email)) {
    back(id, "err", "Esta es una cuenta protegida (demo / revisión de Apple): no se puede suspender ni eliminar desde el panel.");
  }
  const typed = String(formData.get("confirm_email") ?? "").trim().toLowerCase();
  const real = (user.email ?? "").trim().toLowerCase();
  if (!real) back(id, "err", "La cuenta no tiene correo: no se puede confirmar el borrado desde el panel.");
  if (typed !== real) back(id, "err", "El correo escrito no coincide con el de la cuenta. No se borró nada.");

  const { error } = await supabaseAdmin().auth.admin.deleteUser(id);
  if (error) back(id, "err", `No se pudo eliminar la cuenta: ${error.message}`);
  revalidatePath("/clientes");
  redirect(`/clientes?msg=${encodeURIComponent(`Cuenta ${user.email} eliminada para siempre.`)}`);
}
